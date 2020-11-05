local k = import 'ksonnet-util/kausal.libsonnet';
local gateway = import 'loki/gateway.libsonnet';
local loki = import 'loki/loki.libsonnet';
local frontend = import 'loki/query-frontend.libsonnet';
local promtail = import 'promtail/promtail.libsonnet';
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

loki + promtail + gateway {

  // TODO: use helper (or something like it)

  // local myRbac(name) = $.util.namespacedRBAC(name, [
  //     policyRule.new() +
  //     policyRule.withApiGroups(['']) +
  //     policyRule.withResources(['']) +
  //     policyRule.withVerbs(['']),
  //   ]),

  _config+:: {
    namespace: error 'namespace is a required input',
    cluster: error 'cluster is a required input',

    htpasswd_contents:: null,

    stateful_ingesters: true,
    ingester_pvc_class: 'gp2',

    stateful_queriers: true,
    querier_pvc_class: 'gp2',

    storage_backend: 's3',
    s3_address: error 's3_address is required (Ex: us-east-1)',
    s3_bucket_name: error 's3_bucket_name is required',

    ruler_enabled: true,

    // these are defaults 2.0+, included here to be explicit
    using_boltdb_shipper: error 'using_boltdb_shipper is required ({true, false}',
    index_period_hours: error 'index_perios_hours is required ({24,n})',
    boltdb_shipper_shared_store: error 'boltdb_shipper_shared_store is required',

    index_prefix: error 'index_prefix is required',

    promtail_config+: {
      clients: [{
        scheme:: 'http',
        hostname:: 'gateway.%(namespace)s.svc' % $._config,
        container_root_path:: '/var/lib/docker',
      }],
    },

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

  consul_deployment+:
    deployment.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),

  memcached_rbac:
    $.util.namespacedRBAC('memcached', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ]),

  memcached+: {
    statefulSet+:
      statefulSet.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),
  },

  memcached_frontend_rbac:
    $.util.namespacedRBAC('memcached-frontend', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ]),

  memcached_frontend+: {
    statefulSet+:
      statefulSet.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),
  },

  memcached_index_queries_rbac:
    $.util.namespacedRBAC('memcached-index-queries', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ]),
  memcached_index_queries+: {
    statefulSet+:
      statefulSet.spec.template.metadata.withAnnotationsMixin({ 'linkerd.io/inject': 'disabled' }),
  },

  //Add headers for query-frontend health check
  query_frontend_container+::
    container.mixin.readinessProbe.httpGet.withHttpHeaders([
      {
        name: 'X-Scope-OrgID',
        value: '1',
      },
    ]),

  // ***
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

  gateway_rbac:
    $.util.namespacedRBAC('loki-gateway', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ]),
  gateway_deployment+:
    deployment.spec.template.spec.withServiceAccountName('loki-gateway') +
    deployment.spec.template.spec.securityContext.withFsGroup(10001),

  query_frontend_rbac:
    $.util.namespacedRBAC('loki-query-frontend', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ]),
  query_frontend_deployment+:
    deployment.spec.template.spec.withServiceAccountName('loki-query-frontend'),

  //Removing the client config from promtail configmap
  promtail_config +: {
    clients:: null,
  },

  //promtail container arg
  promtail_args+: {
    'client.url': 'http://$(GATEWAY_USERNAME):$(GATEWAY_PASSWORD)@gateway.loki.svc/loki/api/v1/push',
  },

  //Promtail secrets
  promtail_container+: {
    env+: [
      envVar.fromSecretRef('GATEWAY_USERNAME', 'promtail-secret', 'username'),
      envVar.fromSecretRef('GATEWAY_PASSWORD', 'promtail-secret', 'password'),
    ],
  },

  //Hide this secret in generated json. We will manually create this in the cluster for now
  gateway_secret::null

}
