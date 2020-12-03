# observe

Welcome!  You've found reusable configurations for Observability Tooling.

## What this is

A collection of Observability related configuration and tooling meant to:

* to facilitate exploration and experimentation of Cloud Native Observability Tools
* provide examples of Production Grade deployments

Tanka is the preferred configuration language.

## What tools are included thus far

The following are in the process of being added.

Tool      | Status      | What                                 | Where
--------- | ----------- | ------------------------------------ | -----
 k8s-mon  | In progress | [prometheus-ksonnet] + mixins        | _WIP_
 Loki     | In Progress | Distributed grep, and so much more   | [cc-loki-eks]
 Promtail | In Progress | Logging Agent --> Loki               | _WIP_
 Cortex   | On Deck     | horiz-scalable durable metrics store | _WIP_
 Tempo    | On Deck     | horiz-scalable durable trace store   | _WIP_

[cc-loki-eks]: tanka/cc-loki-eks
[prometheus-ksonnet]: https://github.com/grafana/jsonnet-libs/tree/master/prometheus-ksonnet

## Honest Footer

This is still something of a construction zone. Feel free to reach out directly!

The forest steward can be found at [@halcyondude](https://github.com/halcyondude),
CNCF Slack, or Grafana Slack. Happy to chat/collaborate!
