local k = import 'ksonnet-util/kausal.libsonnet';
# local gateway = import 'loki/gateway.libsonnet';
local loki = import 'loki/loki.libsonnet';
local frontend = import 'loki/query-frontend.libsonnet';
local memcached = import 'memcached/memcached.libsonnet';

// these allow leveraging the base types so we can extend them. For more info see:
//
// https://github.com/jsonnet-libs/k8s-alpha/blob/master/1.15/_gen/apps/v1/main.libsonnet
// https://github.com/jsonnet-libs/k8s-alpha/blob/master/1.15/_gen/apps/v1/deploymentSpec.libsonnet
// https://github.com/jsonnet-libs/k8s-alpha/blob/master/1.15/_gen/apps/v1/statefulSetSpec.libsonnet
// https://github.com/jsonnet-libs/k8s-alpha/blob/master/1.15/_gen/core/v1/container.libsonnet
//
local container = k.core.v1.container;
local deployment = k.apps.v1.deployment;
local statefulSet = k.apps.v1.statefulSet;
local daemonSet = k.apps.v1.daemonSet;
local policyRule = k.rbac.v1beta1.policyRule;
local envVar = if std.objectHasAll(k.core.v1, 'envVar') then k.core.v1.envVar else k.core.v1.container.envType;

loki {

  // TODO: use helper (or something like it)

  local minimalRbac(name) = $.util.namespacedRBAC(name, [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ]),

  _config+:: {
    namespace: error 'namespace is a required input',
    cluster: error 'cluster is a required input',

    arn_ingester_sa:      error ' arn_ingester_sa is required',
    arn_querier_sa:       error ' arn_querier_sa is required',
    arm_table_manager_sa: error ' arm_table_manager_sa is required',

    htpasswd_contents:: null,

    stateful_ingesters: true,
    ingester_pvc_class: 'gp2',

    stateful_queriers: true,
    querier_pvc_class: 'gp2',
    compactor_pvc_class: 'gp2',

    storage_backend: 's3',
    s3_address: error 's3_address is required (Ex: us-east-1)',
    s3_bucket_name: error 's3_bucket_name is required',

    ruler_enabled: true,

    // these are defaults 2.0+, included here to be explicit
    using_boltdb_shipper: error 'using_boltdb_shipper is required ({true, false}',
    index_period_hours: error 'index_perios_hours is required ({24,n})',
    boltdb_shipper_shared_store: error 'boltdb_shipper_shared_store is required',

    index_prefix: error 'index_prefix is required',

    replication_factor: 3,
    consul_replicas: 1,

    # https://github.com/grafana/loki/blob/master/docs/sources/operations/storage/boltdb-shipper.md

    loki+: {
      schema_config+: {
        configs: [{
          from: '2020-11-04',
          store: 'boltdb-shipper',
          object_store: 's3',
          schema: 'v11',
          index: {
            prefix: '%s-index.' % $._config.index_prefix,
            period: '%dh' % $._config.index_period_hours,
          },
        }],
      },
    },
  },


  //
  // StatsfulSet - memcached
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


  // TODO: Figure out why helper func only works for memcached, likely because of the wrapping memcache{} block

  //
  // StatsfulSet - Ingester, compactor, querier
  //

  ingester_rbac:
    $.util.namespacedRBAC('ingester', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ]),

  ingester_statefulset+:
    statefulSet.spec.template.spec.withServiceAccountName('ingester') +
    statefulSet.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),

  compactor_rbac:
    $.util.namespacedRBAC('compactor', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ]),

  compactor_statefulset+:
    statefulSet.spec.template.spec.withServiceAccountName('compactor') +
    statefulSet.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),

  querier_rbac:
    $.util.namespacedRBAC('querier', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ]),

  querier_statefulset+:
    statefulSet.spec.template.spec.withServiceAccountName('querier') +
    statefulSet.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),

  //
  // Deployment
  //

  consul_deployment+:
    deployment.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),


  // TODO: surface this and/or fix
  query_frontend_container+::
    container.mixin.readinessProbe.httpGet.withHttpHeaders([
      {
        name: 'X-Scope-OrgID',
        value: '1',
      },
    ]),

  //
  // Deployment
  //
  table_manager_deployment+:
    deployment.spec.template.spec.securityContext.withFsGroup(10001),

  distributor_rbac:
    $.util.namespacedRBAC('loki-distributor', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ]),

  distributor_deployment+:
      deployment.spec.template.spec.withServiceAccountName('loki-distributor'),

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
    $.util.namespacedRBAC('loki-query-frontend', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ]),
  query_frontend_deployment+:
    deployment.spec.template.spec.withServiceAccountName('loki-query-frontend'),
}
