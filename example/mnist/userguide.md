

```bash
$ kubectl -n istio-system get service istio-ingressgateway -o=jsonpath='{.status.loadBalancer.ingress[*].hostname}'

istio-syste-istio-ingres-ebbfc-6315131-70e2128328d8.kr.lb.naverncp.com
```