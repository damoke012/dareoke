FROM nvcr.io/nvidia/clara/clara-parabricks:4.6.0-1

LABEL maintainer="platform-team"
LABEL description="NVIDIA Clara Parabricks for OpenShift"
LABEL version="4.6.0-1"

USER root
RUN echo "Build: $(date)" > /etc/build-info && \
    echo "OpenShift-compatible container" >> /etc/build-info

RUN which pbrun || echo "Warning: pbrun not found"

USER 1001

CMD ["/bin/bash"]
