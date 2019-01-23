#!/bin/bash
#
# Copyright 2019 Google LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [ $# -eq 0 ]
then 
  echo "Please provide GCP project name as first argument to this scripts."
  exit
fi

PROJECT_NAME=$1

export INSTANCE_TEMPLATE_NAME="tf-inference-template"
export IMAGE_FAMILY="tf-latest-cu100" 
export INSTANCE_GROUP_NAME="deeplearning-instance-group"
export HEALTH_CHECK_NAME="http-basic-check"
export WEB_BACKED_SERVICE_NAME="tensorflow-backend"
export WEB_MAP_NAME="map-all"
export LB_NAME="tf-lb"
export IP4_NAME="lb-ip4"
export FORWARDING_RULE="lb-fwd-rule"

# Creates instance template using 16 core, 100GB and 4 T4 gpu machine.
gcloud beta compute --project=$PROJECT_NAME instance-templates create $INSTANCE_TEMPLATE_NAME \
     --machine-type=n1-standard-16 \
     --maintenance-policy=TERMINATE \
     --accelerator=type=nvidia-tesla-t4,count=4 \
     --min-cpu-platform=Intel\ Skylake \
     --tags=http-server,https-server \
     --image-family=$IMAGE_FAMILY \
     --image-project=deeplearning-platform-release \
     --boot-disk-size=100GB \
     --boot-disk-type=pd-ssd \
     --boot-disk-device-name=$INSTANCE_TEMPLATE_NAME \
     --metadata startup-script-url=gs://solutions-public-assets/tensorrt-t4-gpu/start_agent_and_inf_server.sh

# Creates instance group with above template of size 2
gcloud compute instance-groups managed create $INSTANCE_GROUP_NAME \
   --template $INSTANCE_TEMPLATE_NAME \
   --base-instance-name deeplearning-instances \
   --size 2 \
   --zones us-central1-a,us-central1-b

# Set autoscaling based on custom metrics of gpu utilization 
gcloud compute instance-groups managed set-autoscaling $INSTANCE_GROUP_NAME \
   --custom-metric-utilization metric=custom.googleapis.com/gpu_utilization,utilization-target-type=GAUGE,utilization-target=85 \
   --max-num-replicas 4 \
   --cool-down-period 360 \
   --region us-central1

gcloud compute health-checks create http $HEALTH_CHECK_NAME \
   --request-path /v1/models/default \
   --port 8888

gcloud compute instance-groups set-named-ports $INSTANCE_GROUP_NAME \
    --named-ports http:8888 \
    --region us-central1

gcloud compute backend-services create $WEB_BACKED_SERVICE_NAME \
    --protocol HTTP \
    --health-checks $HEALTH_CHECK_NAME \
    --global

gcloud compute backend-services add-backend $WEB_BACKED_SERVICE_NAME \
   --balancing-mode UTILIZATION \
   --max-utilization 0.8 \
   --capacity-scaler 1 \
   --instance-group $INSTANCE_GROUP_NAME \
   --instance-group-region us-central1 \
   --global

gcloud compute url-maps create $WEB_MAP_NAME \
   --default-service $WEB_BACKED_SERVICE_NAME

gcloud compute target-http-proxies create $LB_NAME \
   --url-map $WEB_MAP_NAME

gcloud compute addresses create $IP4_NAME \
   --ip-version=IPV4 \
   --global

export IP=$(gcloud compute addresses list | grep ${IP4_NAME} | awk '{print $2}')

gcloud compute forwarding-rules create $FORWARDING_RULE \
   --address $IP \
   --global \
   --target-http-proxy $LB_NAME \
   --ports 80

gcloud compute firewall-rules create www-firewall-80 \
    --target-tags http-server --allow tcp:80

gcloud compute firewall-rules create www-firewall-8888 \
    --target-tags http-server --allow tcp:8888