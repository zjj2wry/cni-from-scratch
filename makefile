
cni:
	docker build -t mycni/mycni:v0.1.0 .
	kind load docker-image mycni/mycni:v0.1.0

kind:
	# my-cni 脚本依赖 jq 命令
	docker build -t kindest/node:v1.16.3-jq . -f Dockerfile-kindnode

netutils:
	docker pull raarts/netutils
	kind load docker-image raarts/netutils

deploy:
	kubectl apply -f cni.yaml

test:
	kubectl run tmp-"$$RANDOM" -it --image=raarts/netutils --image-pull-policy=IfNotPresent -- bash