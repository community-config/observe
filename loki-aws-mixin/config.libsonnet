{
  _config+:: {
    namespace: error 'namespace is a required input',
    cluster: error 'cluster is a required input',

    // TODO: default these to {} to generalize
    // IAM Roles annotated --> k8s Service Accounts, allowing access to S3
    arn_ingester_sa:      error ' arn_ingester_sa is required',
    arn_querier_sa:       error ' arn_querier_sa is required',
    arn_table_manager_sa: error ' arn_table_manager_sa is required',

    // named k8s secret.  this MUST be created in whatever namespace(s) are used
    image_pull_secret: 'dockerhub-credentials',

      // imagePullSecrets added to each Service Account.
    image_pull_secrets: { 'name': self.image_pull_secret },

    htpasswd_contents:: null,

    // distributor
    distributor_replicas: 6,

    // ingester
    stateful_ingesters: true,
    ingester_pvc_class: 'gp2',
    ingester_replicas: 12,

    // querier
    stateful_queriers: true,
    querier_pvc_class: 'gp2',
    querier_replicas: 6,

    // compactor,
    compactor_pvc_class: 'gp2',

    // consul
    consul_replicas: 1,

    htpasswd_contents:: null,
    ruler_enabled: true,

    storage_backend: 's3',
    s3_address: error 's3_address is required (Ex: us-east-1)',
    s3_bucket_name: error 's3_bucket_name is required',

    ruler_enabled: true,

    // these are defaults 2.0+, included here to be explicit
    using_boltdb_shipper: true,
    index_period_hours: 24,
    boltdb_shipper_shared_store: 's3',

    index_prefix: error 'index_prefix is required',

    # https://github.com/grafana/loki/blob/master/docs/sources/operations/storage/boltdb-shipper.md

    using_boltdb_shipper: true,
    index_period_hours: 24,
    boltdb_shipper_shared_store: 's3',

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
}
