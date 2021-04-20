#!/bin/bash

wait_for_ready_inferenceservice()
{
        target_ns=$1

        while true
        do
		condition1=`kubectl get inferenceservice -n $target_ns -o jsonpath='{.items[0].status.conditions[0].status}'`
		condition2=`kubectl get inferenceservice -n $target_ns -o jsonpath='{.items[0].status.conditions[1].status}'`
		condition3=`kubectl get inferenceservice -n $target_ns -o jsonpath='{.items[0].status.conditions[2].status}'`

		if [[ "$condition1" = "True" && "$condition2" = "True" && "$condition3" = "True" ]];then
			echo "ok inferenceservice ready!"
			break
		else
			echo "pod is starting.. waiting.."
			sleep 2
		fi
        done
}

wait_for_ready()
{
        target_ns=$1

        while true
        do
                actual_ready_pod_cnt=`kubectl -n $target_ns get po | egrep -v 'Completed|READY' | awk -F" " '{print $2}' | cut -d '/' -f 1`
                planned_pod_cnt=`kubectl -n $target_ns get po | egrep -v 'Completed|READY' | awk -F" " '{print $2}' | cut -d '/' -f 2`

                if test "$actual_ready_pod_cnt" = "$planned_pod_cnt"; then
                        echo "ok $target_ns pod is ready"
                        break
                else
                        echo "$target_ns pod is starting.. waiting..."
                        sleep 2
                fi
        done

}

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd $ROOT_DIR

test_component=$1
target_ns=$2

if [ -z $test_component ]
then 
	echo "How to use test shell..."
    echo '1) tfjob : ./test-nkf-install.sh tfjob'
	echo '2) pytorchjob : ./test-nkf-install.sh pytorchjob'
	echo '3) katib : ./test-nkf-install.sh katib $target_namespace ex) ./test-nkf-install.sh katib anonymous'
	echo '4) kfserving : ./test-nkf-install.sh kfserving $target_namespace ex) ./test-nkf-install.sh kfserving anonymous'
	echo '5) kfserving-dex(istio-dex version) : ./test-nkf-install.sh kf-dex $target_namespace ex) ./test-nkf-install.sh kf-dex anonymous'
	echo '6) seldon : ./test-nkf-install.sh seldon $target_namespace ex) ./test-nkf-install.sh seldon seldon-test'
    exit 0 
fi 

### tfjob test start ###
if [ "$test_component" = "tfjob" ];then
	kubectl apply -f $ROOT_DIR/test/job/tf_job_mnist.yaml			### tfjob test 
elif [ "$test_component" = "pytorchjob" ];then
	kubectl apply -f $ROOT_DIR/test/job/pytorch_job_mnist_gloo.yaml	### pytorch test
elif [ "$test_component" = "katib" ];then
	if [ -z $target_ns ];then 
		echo '[INPUT ERROR] Usage : sh test-nkf-install.sh katib $katib_namespace'
		exit 0 
	fi 
	kubectl apply -f $ROOT_DIR/test/katib/random-example.yaml -n $target_ns		### katib test
elif [ "$test_component" = "kfserving" ];then			
	#### kfserving test
	cd $ROOT_DIR/kfserving/sklearn

	target_ns=$2
	if [ -z $target_ns ]
	then 
		echo '[INPUT ERROR] Usage : sh test-nkf-install.sh kfserving $inferenceservice_namespace'
		exit 0 
	fi 

	kubectl apply -f sklearn.yaml -n $target_ns

	wait_for_ready_inferenceservice $target_ns

	SERVICE_HOSTNAME=`kubectl get inferenceservice sklearn-iris -n $target_ns -o jsonpath='{.status.url}' | cut -d "/" -f 3`
	INGRESS_HOST=`kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
	export INGRESS_PORT=80

	curl -v -H "Host: ${SERVICE_HOSTNAME}" http://${INGRESS_HOST}:${INGRESS_PORT}/v1/models/sklearn-iris:predict -d @./iris-input.json

elif [ "$test_component" = "kf-dex" ];then
	### kfserving -dex version test
	cd $ROOT_DIR/kfserving/sklearn

	target_ns=$2
	if [ -z $target_ns ]
	then 
		echo '[INPUT ERROR] Usage : sh test-nkf-install.sh kf-dex $inferenceservice_namespace'
		exit 0 
	fi 

	kubectl apply -f sklearn.yaml -n $target_ns
	wait_for_ready_inferenceservice $target_ns

	INGRESS_HOST=`kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
	STATE=$(curl -s http://$INGRESS_HOST | awk -F 'state=' '{print $2}'  | cut -d"\"" -f 1)
	REQ=$(curl -s "http://${INGRESS_HOST}/dex/auth?client_id=kubeflow-oidc-authservice&redirect_uri=%2Flogin%2Foidc&response_type=code&scope=profile+email+groups+openid&amp;state=${STATE}" | awk -F"req=" '{print $2}' | cut -d"\"" -f 1)
	curl "http://${INGRESS_HOST}/dex/auth/local?req=${REQ}" -H 'Content-Type: application/x-www-form-urlencoded' --data 'login=admin%40kubeflow.org&password=12341234'
	CODE=`curl -s "http://${INGRESS_HOST}/dex/approval?req=${REQ}" | awk -F"code=" '{print $2}' | cut -d "&" -f 1`
	SESSION=`curl -v "http://${INGRESS_HOST}/login/oidc?code=${CODE}&amp;state=${STATE}" 2>&1 | grep authservice_session | awk -F"authservice_session=" '{print $2}' | cut -d ";" -f 1`

	SERVICE_HOSTNAME=`kubectl get inferenceservice sklearn-iris -n $target_ns -o jsonpath='{.status.url}' | cut -d "/" -f 3`
	INGRESS_HOST=`kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`

	curl -v -H "Host: ${SERVICE_HOSTNAME}" -H "Cookie: authservice_session=${SESSION}" http://${INGRESS_HOST}/v1/models/sklearn-iris:predict -d @./iris-input.json

elif [ "$test_component" = "seldon" ];then
	target_ns=$2	
	if [ -z $target_ns ]
	then 
		echo '[INPUT ERROR] Usage : sh test-nkf-install.sh seldon $seldon-core_namespace'
		exit 0 
	fi
	kubectl create ns $target_ns
	INGRESS_HOST=`kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
	kubectl apply -f $ROOT_DIR/test/seldon/seldon.yaml -n $target_ns
	kubectl label namespace $target_ns serving.kubeflow.org/inferenceservice=enable
	
	cat <<EOF | kubectl apply -n $target_ns -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: kubeflow-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - hosts:
    - '$INGRESS_HOST'
    port:
      name: http
      number: 80
      protocol: HTTP
EOF

	wait_for_ready $target_ns

	echo "sleep 10 seconds..."
	sleep 10
		
	curl -s -d '{"data": {"ndarray":[[1.0, 2.0, 5.0]]}}'    -X POST http://$INGRESS_HOST/seldon/$target_ns/seldon-model/api/v1.0/predictions    -H "Content-Type: application/json"
fi


