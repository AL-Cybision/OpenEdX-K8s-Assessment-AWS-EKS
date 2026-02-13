# External References (Upstream Docs)

This repo is self-contained for reproduction (`docs/reproduce.md`), but the links below are the primary upstream references used for design decisions and troubleshooting.

## Open edX (Official)

- https://docs.openedx.org/en/latest/site_ops/index.html
- https://docs.openedx.org/en/latest/site_ops/install_configure_run_guide/index.html
- https://docs.openedx.org/en/latest/site_ops/install_configure_run_guide/configuration/index.html
- https://docs.openedx.org/en/latest/site_ops/install_configure_run_guide/installation/tutor.html
- https://docs.openedx.org/en/latest/community/release_notes/index.html
- https://docs.openedx.org/en/latest/community/release_notes/ulmo.html
- https://openedx.atlassian.net/wiki/spaces/COMM/pages/3613392957/Open+edX+release+schedule
- Open edX Proposals (architecture direction: containers + operator-managed config):
  - https://docs.openedx.org/projects/openedx-proposals/en/latest/architectural-decisions/oep-0045-arch-ops-and-config.html
  - https://docs.openedx.org/projects/openedx-proposals/en/latest/architectural-decisions/oep-0045/decisions/0001-tutor-as-replacement-for-edx-configuration.html

## Tutor (Operator Manual)

- Versioning / release mapping:
  - https://docs.tutor.edly.io/reference/openedx-releases.html
- https://docs.tutor.edly.io/install.html
- https://docs.tutor.edly.io/configuration.html
- https://docs.tutor.edly.io/k8s.html
- https://docs.tutor.edly.io/tutorials/proxy.html
- https://docs.tutor.edly.io/tutorials/scale.html

## AWS EKS + AWS Load Balancer Controller

- https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
- https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
- EBS CSI driver add-on:
  - https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
- https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- https://github.com/kubernetes-sigs/aws-load-balancer-controller

## Kubernetes Ingress Fundamentals

- https://kubernetes.io/docs/concepts/services-networking/ingress/
- ingress-nginx docs:
  - https://kubernetes.github.io/ingress-nginx/
- cert-manager docs (Let’s Encrypt on Kubernetes):
  - https://cert-manager.io/docs/

## Production Blueprints

- https://github.com/cookiecutter-openedx/cookiecutter-openedx-devops
- https://discuss.openedx.org/t/announcing-a-new-cookiecutter-for-deploying-tutor-to-kubernetes-at-scale/6816

## High-signal Troubleshooting Threads

- https://discuss.openedx.org/t/too-many-redirects-error/10883
- https://discuss.openedx.org/t/login-issues-redirection-loop-after-setting-up-studio-on-sub-domain/4029
- https://discuss.openedx.org/t/issue-with-redirect-to-http-on-sign-in-in-studio/10028
