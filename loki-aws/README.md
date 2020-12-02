# loki-aws-mixin - Loki on EKS

- [loki-aws-mixin - Loki on EKS](#loki-aws-mixin---loki-on-eks)
  - [What this is](#what-this-is)
  - [Details](#details)
  - [Work In Progress](#work-in-progress)

## What this is

You've found an opinionated overlay atop Grafana's [Loki Production JSonnet]
that enables a _**Production Grade**_ deployment to AWS's Elastic Kubernetes Service ([EKS]).

[Loki Production JSonnet]: https://github.com/grafana/loki/tree/master/production/ksonnet/loki
[EKS]: https://aws.amazon.com/eks

## Details

- Sane defaults for a basic non-trivial deployment of Loki (12 ingesters, 6 queriers)
- boltdb-shipper --> S3
- Common parameters (number of replicas, Role ARN's, etc) surfaced via `_config::`
- Service Accounts
  - Created for each microservice, enabling k8s cluster administrators to lock down default SA's.  This is a best practice and can help to prevent classes of security incidents that stem from highly permissioned default SA's.
  - Service Account Annotations for role assumption where necessary (e.g. to access S3)
  - Roles, RoleBindings, and PodSecurityPolicies created.
- Ingester, Querier, Compactor
  - Configured to run as `StatefulSet`, with PersistentVolumeClaim types set to EKS default of `gp2` by default (_configurable_)
  - EKS Annotations allowing ingester, querier, and compactor to assume roles (`eks.amazonaws.com/role-arn`)
- Annotations for Linkerd.  If Linkerd is not used, these annotations don't cause issues.
- Support to co-exist w/ FluxCD, should it be in place to own/govern namespace creation.
- Support for using Ingress (vs. the built-in gateway deployment), with a basic mechanism to enable token auth to the endpoint.

## Work In Progress

- <https://github.com/grafana/jsonnet-libs/pull/392> (to enable SA features)
- Loki PR's to move some of this --> base jsonnet
- Cleaning up and parameterizing the Ingress solution
- supporting namespaces other than `loki` (hard-coded in PSP's)
- RBAC for `table-manager` and `ruler`
- Documentation, pictures, and a better readme :)
