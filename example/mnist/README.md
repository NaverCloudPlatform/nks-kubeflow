# MNIST on Kubeflow

This example guides you through the process of taking an example model, modifying it to run better within Kubeflow, and serving the resulting trained model.

Follow the version of the guide that is specific to how you have deployed Kubeflow

<a id=nks></a>
## MNIST on Kubeflow on Naver Kubernetes Service

1. Follow these [instructions](https://https://guide.ncloud-docs.com/docs/ko/vnks-nks-kubeflow-installation/) to install Kubeflow on Ncloud Kubernetes Service.

1. [Setup docker credentials](#docker_credential).

1. Launch a Jupyter Notebook

  * The tutorial is run on Jupyter Tensorflow 1.15 image.

1. Launch a terminal in Jupyter and clone the kubeflow/examples repo

  ```bash
  git clone https://github.com/NaverCloudPlatform/nks-kubeflow.git
  ```

1. Open the notebook `mnist/mnist_nks.ipynb`

1. Follow the notebook to train and deploy on MNIST on Kubeflow

<a id=docker_credential></a>
### Prerequisites

### Configure docker credentials

#### Why do we need this?

Kaniko is used by fairing to build the model every time the notebook is run and deploy a fresh model.
The newly built image is pushed into the DOCKER_REGISTRY and pulled from there by subsequent resources.

Get your docker registry user and password encoded in base64 <br>

`echo -n USER:PASSWORD | base64` <br>

Create a config.json file with your Docker registry url and the previous generated base64 string <br>
```json
{
	"auths": {
		"${REGISTRY_NAME}.kr.ncr.ntruss.com": {
			"auth": "xxxxxxxxxxxxxxx"
		}
	}
}
```

<br>

### Create a config-map in the namespace you're using with the docker config

`kubectl create --namespace ${NAMESPACE} configmap docker-config --from-file=<path to config.json>`

Source documentation: [Kaniko docs](https://github.com/GoogleContainerTools/kaniko#pushing-to-docker-hub)
