#!/bin/bash

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


check_system()
{
        src_data=$@
        idx=0
        org_arr=()
        for value in $src_data
        do
                let idx=${idx}+1
                if [ $idx == 1 ];then
                        op=$value
                elif [ $idx == 2 ];then
                        target_data=$value
                else
                        org_arr+=($value)
                fi
        done

        if [ $op == "lt" ];then
                for val in ${org_arr[@]}; do
                        val=`echo $val | sed 's/[^0-9]*//g'`
                        if [ $val -lt $target_data ];then
                                echo "check system requirements, cpu min : 4 core, mem min : 12GB"
                                exit 1
                        fi
                done
        elif [ $op == "eq" ];then
                for val in ${org_arr[@]}; do
                        kube_node_ver=`echo $val | cut -d "." -f1-2`
                        if [ "$kube_node_ver" != "$target_data" ];then
                                echo "NKS version must be v1.17.xx, your version : ${val}"
                                exit 2
                        fi
                done
        elif [ $op == "in" ];then
                target_data_arr=(${target_data//,/ })
                for val in ${org_arr[@]}; do
                        if [[ " ${target_data_arr[@]} " =~ " ${val} " ]]; then
                                # whatever you want to do when array doesn't contain value
                                echo "namespace check error, use clean nks, $val"
                                exit 3
                        fi
                done
        fi

}

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

dex_enabled=false
if [ -n "$1" ] && [[ $1 = 'dex' ]]; then
	dex_enabled=true
fi

if [ -z $KUBECONFIG ]
then
        echo "\$KUBECONFIG must be set."
        echo "ex) $ export KUBECONFIG="~/Downloads/kubeconfig-1865.yaml""
    	exit 0
fi

### check minimum requirement start
node_cpus=`kubectl get nodes -o=jsonpath="{.items[*]['status.capacity.cpu']}"`
node_mems=`kubectl get nodes -o=jsonpath="{.items[*]['status.capacity.memory']}"`
node_kube_ver=`kubectl get nodes -o=jsonpath="{.items[*]['status.nodeInfo.kubeletVersion']}"`
cur_ns=`kubectl get ns -o=jsonpath="{.items[*]['metadata.name']}"`

#cpu 4 under check
check_system lt 4 $node_cpus

#mem 12GB under check
check_system lt 12000000 $node_mems

check_system eq "v1.17" $node_kube_ver

check_system in "kubeflow,istio-system,kfserving-system,knative-serving,cert-manager,auth" $cur_ns
###  check minimum requirement end 

ISTIO_ROOT=$ROOT_DIR/istio-1.3.1
KUBEFLOW_ROOT=$ROOT_DIR/ncp-kf-resource
KFSERVING_ROOT=$ROOT_DIR/kfserving

### install istio -start
cd $ISTIO_ROOT

for i in install/kubernetes/helm/istio-init/files/crd*yaml; do kubectl apply -f $i; done
kubectl apply -f install/kubernetes/istio-demo.yaml
### install istio -end

wait_for_ready istio-system

### install istio -end
# !!! before install - download kfctl!!!
cd $KUBEFLOW_ROOT

if [ "$dex_enabled" = true ]; then
	kfctl apply -V -f kfctl_istio_dex.v1.1.0.yaml
else
	kfctl apply -V -f kfctl_k8s_istio.v1.1.0.yaml
fi
### install istio -end

wait_for_ready kubeflow

### install kfserving - start
cd $KFSERVING_ROOT
kubectl apply -f 1.serving-crds.yaml
sleep 5
kubectl apply -f 2.serving-core.yaml

wait_for_ready knative-serving

kubectl apply -f 3.release.yaml

wait_for_ready knative-serving

### kfserving
kubectl apply -f $KFSERVING_ROOT/4.kfserving-v0.4.0.yaml
wait_for_ready kfserving-system

### install kfserving - end

### istio - ingress gateway patch
INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
kubectl -n kubeflow patch gateway kubeflow-gateway --type='json' -p='[{"op": "replace", "path": "/spec/servers/0/hosts/0", "value":"'${INGRESS_HOST}'"}]'
kubectl -n kubeflow patch virtualservice centraldashboard --type='json' -p='[{"op": "replace", "path": "/spec/hosts/0", "value":"'${INGRESS_HOST}'"}]'
### istio - ingress gateway patch

echo "end installation..."
