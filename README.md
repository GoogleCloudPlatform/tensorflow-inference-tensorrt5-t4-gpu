<!--
  Licensed to the Apache Software Foundation (ASF) under one or more
  contributor license agreements.  See the NOTICE file distributed with
  this work for additional information regarding copyright ownership.
  The ASF licenses this file to You under the Apache License, Version 2.0
  (the "License"); you may not use this file except in compliance with
  the License.  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
-->

# TensorFlow Inference at scale using Nvidia T4 GPU on Google Cloud Platform

This repository provides scripts to create inference server with auto scaling group based on the GPU utilization.

Repository provides following contents:
- Script server_init.sh which builds complete infrastructure of inference server. It needs only one parameter i.e. Google Cloud project name which will be used to instantiate servers.
- Metrics reporting scripts used by each virtual machine to report GPU usage metrics to Stackdriver.
- Start agent and inference server script which will be used as virtual machine startup script which needs to be copied to Google Cloud Storage bucket which VM can access. For your convience this is already available in public bucket [start_agent_and_inf_server.sh](gs://solutions-public-assets/tensorrt-t4-gpu/start_agent_and_inf_server.sh)
- Third party code to test gpu scaling by spinnig gpu cores for 10 minutes.

## Third party code for testing auto scale based on gpu burn

```bash
git clone https://github.com/GoogleCloudPlatform/tensorflow-inference-tensorrt-t4-gpu.git
cd tensorflow-inference-tensorrt-t4-gpu
git submodule update --init --recursive
cd third_party/gpu-burn
make
./gpu_burn 600 > /dev/null &
```

## Using server_init.sh scripts to build and deploy GPU inference server
Usage: sh server_init.sh <GCP_PROJECT_NAME>
E.g. 
```bash
sh server_init.sh t4_inference_server
```

## Folder metrics_reporting  contains scripts to monitor and report GPU utilization on GCP.
It is very simple to use, just run agent on each of your instance:

```bash
pip install -r ./requirenments.txt
python ./report_gpu_metrics.py &
```

This will auto create the metrics. But if you need to create metrics first run the following commands:

```bash
pip install -r ./requirenments.txt
GOOGLE_CLOUD_PROJECT=<ID> python ./create_gpu_metrics.py
```

## Startup script start_agent_and_inf_server.sh should be used as startup script for deeplearning virtual machines in Google Cloud Platform.

This scripts will only work with virtual machines which has Nvidia GPU attached and has Git, Python and Pip already part of VM image. Also script needs to be copied to Google Cloud Storage bucket which is accessible to the project used by the virtual machines which are being created.

Scripts is responsible for following task in given sequence
1. Install Nvidia drivers
2. Download this repository 
3. Create and initialize service to report GPU metrics.
4. Download specified model to be deployed and then create and initialize inference service.

E.g. of start-script specified in instance template
```bash
export PROJECT_NAME=#your project
export INSTANCE_TEMPLATE_NAME="tf-inference-template"
export IMAGE_FAMILY="tf-latest-cu100" 

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

```
