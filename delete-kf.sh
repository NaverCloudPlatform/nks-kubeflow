#!/bin/bash

#############################################################
# !!!! should be change directory according to server env !!!
#############################################################


ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

ISTIO_ROOT=$ROOT_DIR/istio-1.3.1
KUBEFLOW_ROOT=$ROOT_DIR/ncp-kf-resource
KFSERVING_ROOT=$ROOT_DIR/kfserving

kubectl delete -f $ROOT_DIR/kfserving/4.kfserving-v0.4.0.yaml

cd $KFSERVING_ROOT
kubectl delete -f 1.serving-crds.yaml
kubectl delete -f 2.serving-core.yaml
kubectl delete -f 3.release.yaml

### install istio -start
cd $ISTIO_ROOT

for i in install/kubernetes/helm/istio-init/files/crd*yaml; do kubectl apply -f $i; done
kubectl delete -f install/kubernetes/istio-demo.yaml
### install istio -end

# !!! before install - download kfctl!!!
cd $KUBEFLOW_ROOT
kfctl delete --force-deletion -V -f kfctl_k8s_istio.v1.1.0.yaml

### delete etc
kubectl patch crd profiles.kubeflow.org -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete crd applications.app.k8s.io
kubectl get configmap -o name -n kube-system | egrep 'cert-manager'|xargs kubectl delete -n kube-system
kubectl get mutatingwebhookconfiguration -o name | egrep 'kubeflow|katib'|xargs kubectl delete
kubectl get clusterrole -o name| egrep 'kubeflow|dex'|xargs kubectl delete
kubectl get clusterrolebinding -o name| egrep 'kubeflow|dex'|xargs kubectl delete

