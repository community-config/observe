// core utils and wrappers
local k = import 'ksonnet-util/kausal.libsonnet';

// Loki Core Configuration
# local gateway = import 'loki/gateway.libsonnet';
local loki = import 'loki/loki.libsonnet';
local frontend = import 'loki/query-frontend.libsonnet';
local memcached = import 'memcached/memcached.libsonnet';

// shortcuts to types & helpers used to augment the base Loki config
local container = k.core.v1.container;
local deployment = k.apps.v1.deployment;
local statefulSet = k.apps.v1.statefulSet;
local daemonSet = k.apps.v1.daemonSet;
local policyRule = k.rbac.v1beta1.policyRule;
local envVar = if std.objectHasAll(k.core.v1, 'envVar') then k.core.v1.envVar else k.core.v1.container.envType;
local serviceAccount = k.core.v1.serviceAccount;

loki {

  _config+:: {
    namespace: error 'namespace is a required input',
    cluster: error 'cluster is a required input',

    // TODO: default these to {} to generalize
    // IAM Roles annotated --> k8s Service Accounts, allowing access to S3
    arn_ingester_sa:      error ' arn_ingester_sa is required',
    arn_querier_sa:       error ' arn_querier_sa is required',
    arn_table_manager_sa: error ' arn_table_manager_sa is required',

    // imagePullSecrets added to each Service Account.
    image_pull_secret: 'dockerhub-credentials',
    image_pull_secrets: { 'name': self.image_pull_secret },

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

  // TODO: debug why this doesn't work for non-memcache
  local minimalRbac(name) = $.util.namespacedRBAC(name, [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ],
    pullSecrets=$._config.image_pull_secrets)

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
    $.util.namespacedRBAC('ingester', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
      ],
      annotations={ 'eks.amazonaws.com/role-arn': $._config.arn_ingester_sa },
      pullSecrets=$._config.image_pull_secrets),

  ingester_statefulset+:
    statefulSet.spec.template.spec.withServiceAccountName('ingester'),

  compactor_rbac:
    $.util.namespacedRBAC('compactor', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ],
    annotations={ 'eks.amazonaws.com/role-arn': $._config.arn_compactor_sa },
    pullSecrets=$._config.image_pull_secrets),

  compactor_statefulset+:
    statefulSet.spec.template.spec.withServiceAccountName('compactor'),

  querier_rbac:
    $.util.namespacedRBAC('querier', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ],
    annotations={ 'eks.amazonaws.com/role-arn': $._config.arn_querier_sa },
    pullSecrets=$._config.image_pull_secrets),

  querier_statefulset+:
    statefulSet.spec.template.spec.withServiceAccountName('querier'),

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
    $.util.namespacedRBAC('table-manager', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ],
    pullSecrets=$._config.image_pull_secrets),

  table_manager_deployment+:
    deployment.spec.template.spec.securityContext.withFsGroup(10001) +
    deployment.spec.template.spec.withServiceAccountName('table-manager'),

  distributor_rbac:
    $.util.namespacedRBAC('distributor', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ], pullSecrets=$._config.image_pull_secrets),

  distributor_deployment+:
      deployment.spec.template.spec.withServiceAccountName('distributor'),

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
    $.util.namespacedRBAC('query-frontend', [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['']) +
      policyRule.withVerbs(['']),
    ],
    pullSecrets=$._config.image_pull_secrets),

  query_frontend_deployment+:
    deployment.spec.template.spec.withServiceAccountName('query-frontend'),
}
