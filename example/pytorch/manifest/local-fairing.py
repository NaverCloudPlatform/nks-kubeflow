import uuid
from kubeflow import fairing
from kubeflow.fairing.kubernetes import utils as k8s_utils

#Registry Endpoint - 본인의 Container Registry endpoint 값으로 변경
CONTAINER_REGISTRY ='test.kr.ncr.ntruss.com' 

#Kubernetes Namespace - 작업이 이루어질 Namespace 값으로 변경
namespace = 'local-test'
job_name = f'cifar10-job-{uuid.uuid4().hex[:4]}'

command=["python", "cifar10.py"]
output_map = {
    "Dockerfile": "Dockerfile",
    "cifar10.py": "cifar10.py"
}

fairing.config.set_preprocessor('python', command=command, path_prefix="/app", output_map=output_map)

fairing.config.set_builder('docker', registry=CONTAINER_REGISTRY, image_name="pytorch-cifar10", dockerfile_path="Dockerfile")

# Job의 결과물인 모델을 저장할 볼륨 정보 입력
# type : pvc
# pvc : cifar10-pvc
fairing.config.set_deployer('job', namespace=namespace, job_name=job_name,
                            pod_spec_mutators=[k8s_utils.volume_mounts('pvc','cifar10-pvc',mount_path='/mnt/pv')],
                            cleanup=False, stream_log=True)

fairing.config.run()
