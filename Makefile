.PHONY: help all create delete deploy check clean test load-test reset-prometheus reset-grafana jumpbox target

K8S ?= "kind"

help :
	@echo "Usage:"
	@echo "   make all              - create a cluster and deploy the apps"
	@echo "   make create           - create a kind cluster"
	@echo "   make delete           - delete the kind cluster"
	@echo "   make deploy           - deploy the apps to the cluster"
	@echo "   make check            - check the endpoints with curl"
	@echo "   make clean            - delete the apps from the cluster"
	@echo "   make test             - run a LodeRunner test (generates warnings)"
	@echo "   make load-test        - run a 60 second load test"
	@echo "   make reset-prometheus - reset the Prometheus volume (existing data is deleted)"
	@echo "   make reset-grafana    - reset the Grafana volume (existing data is deleted)"
	@echo "   make jumpbox          - deploy a 'jumpbox' pod"

all : delete create deploy jumpbox check

delete :
	# delete the cluster (if exists)
	@# this will fail harmlessly if the cluster does not exist
	@kind delete cluster

create :
	# create the cluster and wait for ready
	@# this will fail harmlessly if the cluster exists
	@# default cluster name is kind

	@kind create cluster --config deploy/kind/kind.yaml

	# wait for cluster to be ready
	@kubectl wait node --for condition=ready --all --timeout=60s

deploy :
	# deploy the app
	@# continue on most errors
	-kubectl apply -f deploy/ngsa-memory

	# deploy prometheus and grafana
	-kubectl apply -f deploy/prometheus
	-kubectl apply -f deploy/grafana

	# deploy fluent bit
	-kubectl create secret generic log-secrets --from-literal=WorkspaceId=dev --from-literal=SharedKey=dev
	-kubectl apply -f deploy/fluentbit/account.yaml
	-kubectl apply -f deploy/fluentbit/log.yaml
	-kubectl apply -f deploy/fluentbit/stdout-config.yaml
	-kubectl apply -f deploy/fluentbit/fluentbit-pod.yaml

	# deploy LodeRunner after the app starts
	@kubectl wait pod ngsa-memory --for condition=ready --timeout=30s
	-kubectl apply -f deploy/loderunner

	# deploy RelayRunner backend after the app starts
	@kubectl wait pod loderunner --for condition=ready --timeout=30s
	-kubectl apply -f deploy/relayrunner-backend

	# deploy RelayRunner client after the backend server starts
	@kubectl wait pod relayrunner-backend --for condition=ready --timeout=30s
	-kubectl apply -f deploy/relayrunner-client

	# wait for the pods to start
	@kubectl wait pod -n monitoring --for condition=ready --all --timeout=30s
	@kubectl wait pod fluentb --for condition=ready --timeout=30s
	@kubectl wait pod loderunner --for condition=ready --timeout=30s
	@kubectl wait pod relayrunner-backend --for condition=ready --timeout=30s
	@kubectl wait pod relayrunner-client --for condition=ready --timeout=30s

	# display pod status
	@kubectl get po -A | grep "default\|monitoring"

check :
	# curl all of the endpoints
	@curl localhost:30080/version
	@echo "\n"
	@curl localhost:30088/version
	@echo "\n"
	@curl localhost:30000
	@curl localhost:32000
	@curl localhost:32080
	@curl localhost:32088/graphql

clean :
	# delete the deployment
	@# continue on error
	-kubectl delete -f deploy/relayrunner-client --ignore-not-found=true
	-kubectl delete -f deploy/relayrunner-backend --ignore-not-found=true
	-kubectl delete -f deploy/loderunner --ignore-not-found=true
	-kubectl delete -f deploy/ngsa-memory --ignore-not-found=true
	-kubectl delete ns monitoring --ignore-not-found=true
	-kubectl delete -f deploy/fluentbit/fluentbit-pod.yaml --ignore-not-found=true
	-kubectl delete secret log-secrets --ignore-not-found=true

	# show running pods
	@kubectl get po -A

test :
	# run a single test
	webv -s http://localhost:30080 -f baseline.json

load-test :
	# run a 60 second load test
	webv -s http://localhost:30080 -f benchmark.json -r -l 1 --duration 60

reset-prometheus :
	# remove and create the /prometheus volume
	@sudo rm -rf /prometheus
	@sudo mkdir -p /prometheus
	@sudo chown -R 65534:65534 /prometheus

reset-grafana :
	# remove and copy the data to /grafana volume
	@sudo rm -rf /grafana
	@sudo mkdir -p /grafana
	@sudo cp -R deploy/grafanadata/grafana.db /grafana
	@sudo chown -R 472:472 /grafana

jumpbox :
	@# start a jumpbox pod
	@-kubectl delete pod jumpbox --ignore-not-found=true

	@kubectl run jumpbox --image=alpine --restart=Always -- /bin/sh -c "trap : TERM INT; sleep 9999999999d & wait"
	@kubectl wait pod jumpbox --for condition=ready --timeout=30s
	@kubectl exec jumpbox -- /bin/sh -c "apk update && apk add bash curl httpie" > /dev/null
	@kubectl exec jumpbox -- /bin/sh -c "echo \"alias ls='ls --color=auto'\" >> /root/.profile && echo \"alias ll='ls -lF'\" >> /root/.profile && echo \"alias la='ls -alF'\" >> /root/.profile && echo 'cd /root' >> /root/.profile" > /dev/null

	#
	# use kje <command>
	# kje http ngsa-memory:8080/version
	# kje bash -l
