# ha-k8s


kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.48.1/deploy/static/provider/baremetal/deploy.yaml


kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- https://url; done"

    - --oidc-issuer-url=https://accounts.google.com
    - --oidc-client-id=
    - --oidc-username-claim=email
