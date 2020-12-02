// core utils and wrappers
local k = import 'ksonnet-util/kausal.libsonnet';

// Loki Core Configuration
# local gateway = import 'loki/gateway.libsonnet';
local loki = import 'loki/loki.libsonnet';
local frontend = import 'loki/query-frontend.libsonnet';
local memcached = import 'memcached/memcached.libsonnet';

// shortcuts to types & helpers used to augment the base Loki config
local container = k.core.v1.container;
local daemonSet = k.apps.v1.daemonSet;
local deployment = k.apps.v1.deployment;
local namespace = k.core.v1.namespace;
local policyRule = k.rbac.v1beta1.policyRule;
local serviceAccount = k.core.v1.serviceAccount;
local statefulSet = k.apps.v1.statefulSet;

local envVar = if std.objectHasAll(k.core.v1, 'envVar') then k.core.v1.envVar else k.core.v1.container.envType;

loki {

  // flux owns this kind: Namespace, as does tanka.
  // This prevents tanka from removing the annotation causing hilarity as pods
  // are not injected until flux re-adds the annotation.
  namespace+:
    namespace.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'enabled' }),

  // TODO: refactor as jsonnet and create PR's for prometheus-ksonnet
  // TODO: the namespace is presently hard coded to "loki"
  // TODO: add SA's and PSP's for table-manager
  loki_psp:   std.native('parseYaml')(importstr 'loki-psp.yaml'),

  local emptyPolicy = [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ],

  // TODO: debug why this doesn't work for non-memcache
  local minimalRbac(name) = $.util.namespacedRBAC(name, emptyPolicy, pullSecrets=$._config.image_pull_secrets),

  //
  // StatefulSets - memcached
  //

  memcached_chunks+: {
    rbac:
      minimalRbac('memcached-chunks'),

    statefulSet+:
      statefulSet.spec.template.spec.withServiceAccountName('memcached-chunks') +
      statefulSet.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),
  },

  memcached_frontend+: {
    rbac:
      minimalRbac('memcached-frontend'),

    statefulSet+:
      statefulSet.spec.template.spec.withServiceAccountName('memcached-frontend') +
      statefulSet.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),
  },

  memcached_index_queries+: {
    rbac:
      minimalRbac('memcached-index-queries'),

    statefulSet+:
      statefulSet.spec.template.spec.withServiceAccountName('memcached-index-queries') +
      statefulSet.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),
  },

  //
  // StatsfulSet - Ingester, compactor, querier
  //

  ingester_rbac:
    $.util.namespacedRBAC('ingester', emptyPolicy,
      annotations={ 'eks.amazonaws.com/role-arn': $._config.arn_ingester_sa },
      pullSecrets=$._config.image_pull_secrets),

  ingester_statefulset+:
    statefulSet.spec.template.spec.withServiceAccountName('ingester') +
    statefulSet.mixin.spec.withReplicas($._config.ingester_replicas),

  compactor_rbac:
    $.util.namespacedRBAC('compactor', emptyPolicy,
    annotations={ 'eks.amazonaws.com/role-arn': $._config.arn_compactor_sa },
    pullSecrets=$._config.image_pull_secrets),

  compactor_statefulset+:
    statefulSet.spec.template.spec.withServiceAccountName('compactor'),

  querier_rbac:
    $.util.namespacedRBAC('querier', emptyPolicy,
    annotations={ 'eks.amazonaws.com/role-arn': $._config.arn_querier_sa },
    pullSecrets=$._config.image_pull_secrets),

  querier_statefulset+:
    statefulSet.spec.template.spec.withServiceAccountName('querier') +
    statefulSet.mixin.spec.withReplicas($._config.querier_replicas),

  //
  // Deployment
  //

  // TODO: consul creates it's own SA, need to patch that.
  consul_deployment+:
    deployment.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),

  //
  // Deployments
  //
  table_manager_rbac:
    $.util.namespacedRBAC('table-manager', emptyPolicy,
    pullSecrets=$._config.image_pull_secrets),

  table_manager_deployment+:
    deployment.spec.template.spec.securityContext.withFsGroup(10001) +
    deployment.spec.template.spec.withServiceAccountName('table-manager'),

  distributor_rbac:
    $.util.namespacedRBAC('distributor', emptyPolicy,
    pullSecrets=$._config.image_pull_secrets),

  distributor_deployment+:
      deployment.spec.template.spec.withServiceAccountName('distributor') +
      deployment.mixin.spec.withReplicas($._config.distributor_replicas),

  // Gateway is not used, Ingress instead.
  //
  // gateway_rbac:
  //   $.util.namespacedRBAC('loki-gateway', [
  //     policyRule.new() +
  //     policyRule.withApiGroups(['']) +
  //     policyRule.withResources(['']) +
  //     policyRule.withVerbs(['']),
  //   ]),
  // gateway_deployment+:
  //   deployment.spec.template.spec.withServiceAccountName('loki-gateway') +
  //   deployment.spec.template.spec.securityContext.withFsGroup(10001),

  query_frontend_rbac:
    $.util.namespacedRBAC('query-frontend', emptyPolicy,
    pullSecrets=$._config.image_pull_secrets),

  query_frontend_deployment+:
    deployment.spec.template.spec.withServiceAccountName('query-frontend'),
}
