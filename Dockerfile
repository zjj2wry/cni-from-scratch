FROM raarts/netutils:latest
RUN apt-get update && apt-get install -y jq iptables
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.16.3/bin/linux/amd64/kubectl
RUN chmod +x ./kubectl
RUN mv ./kubectl /usr/local/bin/kubectl
ADD . /data/app/
WORKDIR /data/app
RUN chmod +x init.sh my-cni
CMD ["./init.sh"]