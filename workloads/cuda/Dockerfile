FROM nvidia/cuda:12.3.2-devel-ubuntu22.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends cmake git make g++ && \
    rm -rf /var/lib/apt/lists/*

# Clone only the two samples needed — avoids pulling the full 1 GB repo
RUN git clone --depth 1 --filter=blob:none --sparse \
      https://github.com/NVIDIA/cuda-samples.git /tmp/cuda-samples && \
    cd /tmp/cuda-samples && \
    git sparse-checkout set \
      Samples/1_Utilities/deviceQuery \
      Samples/1_Utilities/bandwidthTest \
      Common

RUN cd /tmp/cuda-samples/Samples/1_Utilities/deviceQuery  && make && \
    cd /tmp/cuda-samples/Samples/1_Utilities/bandwidthTest && make

RUN mkdir -p \
      /opt/cuda-samples/Samples/1_Utilities/deviceQuery \
      /opt/cuda-samples/Samples/1_Utilities/bandwidthTest && \
    cp /tmp/cuda-samples/Samples/1_Utilities/deviceQuery/deviceQuery \
       /opt/cuda-samples/Samples/1_Utilities/deviceQuery/ && \
    cp /tmp/cuda-samples/Samples/1_Utilities/bandwidthTest/bandwidthTest \
       /opt/cuda-samples/Samples/1_Utilities/bandwidthTest/ && \
    rm -rf /tmp/cuda-samples

COPY cuda-test.sh /scripts/cuda-test.sh
RUN chmod +x /scripts/cuda-test.sh

CMD ["bash", "/scripts/cuda-test.sh"]
