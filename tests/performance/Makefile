OS_ARCH ?= $(shell uname | awk '{print tolower($0)}')
KYMA_DOMAIN ?= $(shell kubectl get configmap -n kube-system shoot-info -o jsonpath="{.data.domain}")

load-testing/charts/plutono:
	mkdir load-testing/charts
	curl -sL https://github.com/credativ/helmcharts/releases/download/plutono-0.1.0/plutono-0.1.0.tgz > plutono.tgz
	tar -xf plutono.tgz -C load-testing/charts

deploy-helm:
	helm dependency update load-testing

	helm upgrade --install load-testing load-testing --set IngressGatewayIP=$(shell ip=$$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); hostname=$$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'); if [ -n "$$ip" ]; then echo "$$ip"; else echo "$$hostname"; fi) --set Domain=${KYMA_DOMAIN} --create-namespace --wait
	@bash -c 'until code="$$(curl -s -o /dev/null -w "%{http_code}" "https://hello.${KYMA_DOMAIN}/get")" && [ "$$code" = "200" ]; do echo "Waiting for 200 OK from https://hello.${KYMA_DOMAIN}/get - received status code: $$code"; sleep 10; done'

test-deploy:
	kubectl rollout status deployment/load-testing
	kubectl cp scripts/common.js $(shell kubectl get pods --selector=app=k6 -o jsonpath='{.items[0].metadata.name}'):run.js -c k6-alpine

test-performance: deploy-max-replicas-istio deploy-helm test-deploy
	kubectl patch deployment/load-testing --type merge --patch-file istio-disabled.yaml
	kubectl rollout status deployment/load-testing
	kubectl exec -q $(shell kubectl get pods --selector=app=k6 -o jsonpath='{.items[0].metadata.name}') -- k6 run run.js -d 1m --vus 500 --out influxdb=http://load-testing-influxdb:8086/k6 --log-output none --system-tags=method,name,status,tag -e DOMAIN=${KYMA_DOMAIN};\
	EXIT_CODE=$$?;\
	echo "Performance test without sidecar test completed with exit code $$EXIT_CODE"
	sleep 5
	kubectl cp $(shell kubectl get pods --selector=app=k6 -o jsonpath='{.items[0].metadata.name}'):summary.html summary-no-sidecar.html

	kubectl patch deployment/load-testing --type merge --patch-file istio-enabled.yaml
	kubectl rollout status deployment/load-testing
	kubectl exec -q $(shell kubectl get pods --selector=app=k6 -o jsonpath='{.items[0].metadata.name}') -- k6 run run.js -d 1m --vus 500 --out influxdb=http://load-testing-influxdb:8086/k6 --log-output none --system-tags=method,name,status,tag -e DOMAIN=${KYMA_DOMAIN};\
	EXIT_CODE=$$?;\
	echo "Performance test with sidecar test completed with exit code $$EXIT_CODE"
	sleep 5
	kubectl cp $(shell kubectl get pods --selector=app=k6 -o jsonpath='{.items[0].metadata.name}'):summary.html summary-sidecar.html

	cd hack/puppeteer && KYMA_DOMAIN=${KYMA_DOMAIN} ./export.sh

test-performance-web: deploy-max-replicas-istio deploy-helm test-deploy
	kubectl patch deployment/load-testing --type merge --patch-file istio-disabled.yaml
	kubectl rollout status deployment/load-testing
	sleep 60
	kubectl exec -q $(shell kubectl get pods --selector=app=k6 -o jsonpath='{.items[0].metadata.name}') -- k6 run run.js -d 1m --vus 500 --log-output none --system-tags=method,name,status,tag -e DOMAIN=${KYMA_DOMAIN} -e K6_WEB_DASHBOARD=true -e K6_WEB_DASHBOARD_EXPORT=summary.html;\
	EXIT_CODE=$$?;\
	echo "Performance test without sidecar test completed with exit code $$EXIT_CODE"
	sleep 5
	kubectl cp $(shell kubectl get pods --selector=app=k6 -o jsonpath='{.items[0].metadata.name}'):summary.html summary-no-sidecar.html

	kubectl patch deployment/load-testing --type merge --patch-file istio-enabled.yaml
	kubectl rollout status deployment/load-testing
	sleep 60
	kubectl exec -q $(shell kubectl get pods --selector=app=k6 -o jsonpath='{.items[0].metadata.name}') -- k6 run run.js -d 1m --vus 500 --log-output none --system-tags=method,name,status,tag -e DOMAIN=${KYMA_DOMAIN} -e K6_WEB_DASHBOARD=true -e K6_WEB_DASHBOARD_EXPORT=summary.html;\
	EXIT_CODE=$$?;\
	echo "Performance test with sidecar test completed with exit code $$EXIT_CODE"
	sleep 5
	kubectl cp $(shell kubectl get pods --selector=app=k6 -o jsonpath='{.items[0].metadata.name}'):summary.html summary-sidecar.html

deploy-max-replicas-istio:
	kubectl apply -f istio-max-replicas.yaml
	kubectl wait --for='jsonpath={.status.state}=Ready' --timeout=5m -n kyma-system istio default
	kubectl wait -n istio-system --for=jsonpath='{.status.loadBalancer.ingress}' --timeout=5m service/istio-ingressgateway

.PHONY: test-performance deploy-max-replicas-istio deploy-helm test-deploy
