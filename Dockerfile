FROM ubuntu:18.04 AS deps

RUN apt-get update && apt-get -y install wget
WORKDIR /tmp
RUN wget https://downloads.apache.org/spark/spark-2.4.5/spark-2.4.5-bin-hadoop2.7.tgz \
	&& tar xvzf spark-2.4.5-bin-hadoop2.7.tgz 


# Runtime Container Image. Adapted from the official Spark runtime 
# image from the project repository at https://github.com/apache/spark.
FROM openjdk:8-jdk-slim AS build

# Spark UID
ARG spark_uid=185

# Install Spark Dependencies and Prepare Spark Runtime Environment
RUN set -ex && \
    apt-get update && \
    ln -s /lib /lib64 && \
    apt install -y bash tini libc6 libpam-modules libnss3 wget python3 python3-pip && \
    mkdir -p /opt/spark && \
    mkdir -p /opt/spark/examples && \
    mkdir -p /opt/spark/work-dir && \
    touch /opt/spark/RELEASE && \
    rm /bin/sh && \
    ln -sv /bin/bash /bin/sh && \
    ln -sv /usr/bin/tini /sbin/tini && \
    echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su && \
    chgrp root /etc/passwd && chmod ug+rw /etc/passwd && \
    ln -sv /usr/bin/python3 /usr/bin/python && \
    ln -sv /usr/bin/pip3 /usr/bin/pip \
    rm -rf /var/cache/apt/*

# Install Kerberos Client and Auth Components
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
  && apt install -yqq krb5-user \
  && rm -rf /var/cache/apt/*


# Copy previously fetched runtime components
COPY --from=deps /tmp/spark-2.4.5-bin-hadoop2.7/bin /opt/spark/bin
COPY --from=deps /tmp/spark-2.4.5-bin-hadoop2.7/jars /opt/spark/jars
COPY --from=deps /tmp/spark-2.4.5-bin-hadoop2.7/python /opt/spark/python
COPY --from=deps /tmp/spark-2.4.5-bin-hadoop2.7/R /opt/spark/R
COPY --from=deps /tmp/spark-2.4.5-bin-hadoop2.7/sbin /opt/spark/sbin
COPY --from=deps /tmp/spark-2.4.5-bin-hadoop2.7/yarn /opt/spark/yarn
ADD start-common.sh start-worker.sh start-master.sh /opt/spark/sbin/


# Copy Docker entry script
COPY --from=deps /tmp/spark-2.4.5-bin-hadoop2.7/kubernetes/dockerfiles/spark/entrypoint.sh /opt/

# COpy examples, data, and tests
COPY --from=deps /tmp/spark-2.4.5-bin-hadoop2.7/examples /opt/spark/examples
COPY --from=deps /tmp/spark-2.4.5-bin-hadoop2.7/data /opt/spark/data
COPY --from=deps /tmp/spark-2.4.5-bin-hadoop2.7/kubernetes/tests /opt/spark/tests

# Replace out of date dependencies causing a 403 error on job launch
WORKDIR /tmp
RUN cd /tmp \
  && wget https://oak-tree.tech/documents/59/kubernetes-client-4.6.4.jar \
  && wget https://oak-tree.tech/documents/58/kubernetes-model-4.6.4.jar \
  && wget https://oak-tree.tech/documents/57/kubernetes-model-common-4.6.4.jar \
  && rm -rf /opt/spark/jars/kubernetes-client-* \
  && rm -rf /opt/spark/jars/kubernetes-model-* \
  && rm -rf /opt/spark/jars/kubernetes-model-common-* \
  && mv /tmp/kubernetes-* /opt/spark/jars/


# Set Spark runtime options
ENV SPARK_HOME /opt/spark

WORKDIR /opt/spark/work-dir
RUN chmod g+w /opt/spark/work-dir
RUN chmod +x /opt/spark/sbin/
ENTRYPOINT [ "/opt/entrypoint.sh" ]

# Specify the User that the actual main process will run as
USER ${spark_uid}
