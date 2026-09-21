# Spring PetClinic Capstone Application

This repository extends the official [Spring PetClinic](https://github.com/spring-projects/spring-petclinic)
application with container images, Helm deployments, and GCP delivery workflows.

## Capstone delivery (Helm / GKE)

Production path for this fork:

| Piece | Location |
|-------|----------|
| Dockerfile | [`Dockerfile`](Dockerfile) at repo root (Temurin 17 JRE, non-root `petclinic` user) |
| Helm chart | [`chart/petclinic`](chart/petclinic) |
| Env values | `values-dev.yaml` / `values-prod.yaml` |
| PR / release CI | [`.github/workflows/pr-release.yml`](.github/workflows/pr-release.yml), [`.github/workflows/main-release.yml`](.github/workflows/main-release.yml) |
| Deploy workflow | [`.github/workflows/manual-deploy.yml`](.github/workflows/manual-deploy.yml) |

App resources deploy to the **`petclinic`** namespace (not `default`). That namespace must match the Workload Identity binding in the infra repo (`petclinic/petclinic` → GCP app SA).

### CI runners (ARC + Kaniko)

App workflows run on **Actions Runner Controller** scale sets in the env GKE cluster (`petclinic-arc-dev` / `petclinic-arc-prod`), not on long-lived GCE VMs.

| Workflow | `runs-on` | Registry |
|----------|-----------|----------|
| PR gatekeeper | `petclinic-arc-dev` | **dev** Artifact Registry only |
| Main release | `petclinic-arc-prod` | **prod** Artifact Registry only |
| Manual deploy | `petclinic-arc-${{ environment }}` | reads the matching env registry |

**Trust model:** runner pods use GKE Workload Identity (`arc-runners` K8s SA → `github-app-runner-sa-{env}`). There is no GitHub→GCP OIDC in these workflows (`id-token: write` is intentionally absent). Images are built with **Kaniko** (no Docker socket / DinD); Trivy scans the image tar before `crane` push.

### GitHub Actions variables

Project identifiers are **not** secrets. Set these as repository (or environment) **Actions variables** under Settings → Secrets and variables → Actions → Variables:

| Variable | Used by | Example |
|----------|---------|---------|
| `GCP_PROJECT_ID` | PR / main / manual-deploy | `my-gcp-project` |
| `GCP_REGION` | PR / main / manual-deploy | `europe-west1` |

Workflows fail fast if either variable is empty. Keep authenticators (tokens, PEMs, passwords) as secrets — not these IDs.

Committed `values-dev.yaml` / `values-prod.yaml` hold only env-specific non-project settings (replicas, ingress host, `environment` label, K8s SA **name**). Project-bound Helm fields are injected at deploy time from the variables above (deterministic names matching the infra modules):

- `image.repository` → `{REGION}-docker.pkg.dev/{PROJECT_ID}/petclinic-repo-{env}/petclinic`
- `googleProjectId` → `$GCP_PROJECT_ID`
- `serviceAccount.gcpEmail` → `petclinic-sa-{env}@$GCP_PROJECT_ID.iam.gserviceaccount.com`
- `cloudSql.instanceConnectionName` → `$GCP_PROJECT_ID:$GCP_REGION:petclinic-db-{env}`

`manual-deploy.yml` passes those via `--set`. Chart defaults leave them empty so a render without `--set` fails closed.

```bash
# Example (credentials and cluster already configured)
PROJECT_ID=<GCP_PROJECT_ID>
REGION=<GCP_REGION>
ENV=dev
helm upgrade --install petclinic ./chart/petclinic \
  --namespace petclinic \
  --create-namespace \
  --values ./chart/petclinic/values-${ENV}.yaml \
  --set image.repository=${REGION}-docker.pkg.dev/${PROJECT_ID}/petclinic-repo-${ENV}/petclinic \
  --set image.tag=<tag> \
  --set googleProjectId=${PROJECT_ID} \
  --set serviceAccount.gcpEmail=petclinic-sa-${ENV}@${PROJECT_ID}.iam.gserviceaccount.com \
  --set cloudSql.instanceConnectionName=${PROJECT_ID}:${REGION}:petclinic-db-${ENV} \
  --wait
```

External access is via the **ingress-nginx LoadBalancer** (source-restricted in infra), not the app ClusterIP Service. Actuator is limited to `health`, `info`, and `prometheus`; probes use `/actuator/health/liveness` and `/actuator/health/readiness`.

### Monitoring (Prometheus / Grafana)

**Primary cluster path:** the chart’s `ServiceMonitor` scrapes Service port `http-web` → `/actuator/prometheus` (Micrometer). Prometheus job label is `petclinic` (`jobLabel: app.kubernetes.io/name`). Alerts live in `PrometheusRule` (e.g. `PetclinicInstanceDown`); the Micrometer JVM dashboard ConfigMap is labeled `grafana_dashboard: "1"` for the Grafana sidecar.

**Non-primary:** the image still runs the JMX Prometheus Java agent on container port `9093` for local/debug use. That port is **not** on the Kubernetes Service and is **not** scraped in-cluster.

Infra stack details (retention, Grafana password, demo checklist): [capstone-project-infra docs/monitoring.md](https://github.com/njakov/capstone-project-infra/blob/main/docs/monitoring.md).

Legacy manifests under [`k8s/`](k8s/) are **local demos only** — do not apply them to the GKE clusters.

Infrastructure (GKE, Cloud SQL, WI, Ingress, monitoring) lives in [capstone-project-infra](https://github.com/njakov/capstone-project-infra).

---

## Understanding the Spring Petclinic application with a few diagrams

See the presentation here:
[Spring Petclinic Sample Application (legacy slides)](https://speakerdeck.com/michaelisvy/spring-petclinic-sample-application?slide=20)

> **Note:** These slides refer to a legacy, pre–Spring Boot version of Petclinic and may not reflect the current Spring Boot–based implementation.
> For up-to-date information, please refer to this repository and its documentation.


## Run Petclinic locally

Spring Petclinic is a [Spring Boot](https://spring.io/guides/gs/spring-boot) application built using [Maven](https://spring.io/guides/gs/maven/) or [Gradle](https://spring.io/guides/gs/gradle/).
Java 17 or later is required for the build, and the application can run with Java 17 or newer.

You first need to clone the project locally:

```bash
git clone https://github.com/spring-projects/spring-petclinic.git
cd spring-petclinic
```
If you are using Maven, you can start the application on the command-line as follows:

```bash
./mvnw spring-boot:run
```
With Gradle, the command is as follows:

```bash
./gradlew bootRun
```

You can then access the Petclinic at <http://localhost:8080/>.

<img width="1042" alt="petclinic-screenshot" src="https://cloud.githubusercontent.com/assets/838318/19727082/2aee6d6c-9b8e-11e6-81fe-e889a5ddfded.png">

You can, of course, run Petclinic in your favorite IDE.
See below for more details.

## Building a Container

This fork ships a root [`Dockerfile`](Dockerfile) used by the CI pipelines (JAR + checksum-pinned JMX agent). Build after assembling the JAR:

```bash
./mvnw -DskipTests package
# CI stages spring-petclinic.jar + jmx.jar before the image build
docker build -t petclinic:local .
```

CI on ARC uses Kaniko instead of `docker build` (same Dockerfile).

You can also build a container image with the Spring Boot build plugin (if you have a docker daemon):

```bash
./mvnw spring-boot:build-image
```

## Running the Container Image

```bash
docker images | grep petclinic
docker run -p 8080:8080 docker.io/library/spring-petclinic:latest
```

## In case you find a bug/suggested improvement for Spring Petclinic

Our issue tracker is available [here](https://github.com/spring-projects/spring-petclinic/issues).

## Database configuration

In its default configuration, Petclinic uses an in-memory database (H2) which
gets populated at startup with data. The h2 console is exposed at `http://localhost:8080/h2-console`,
and it is possible to inspect the content of the database using the `jdbc:h2:mem:<uuid>` URL. The UUID is printed at startup to the console.

A similar setup is provided for MySQL and PostgreSQL if a persistent database configuration is needed. Note that whenever the database type changes, the app needs to run with a different profile: `spring.profiles.active=mysql` for MySQL or `spring.profiles.active=postgres` for PostgreSQL. See the [Spring Boot documentation](https://docs.spring.io/spring-boot/how-to/properties-and-configuration.html#howto.properties-and-configuration.set-active-spring-profiles) for more detail on how to set the active profile.

You can start MySQL or PostgreSQL locally with whatever installer works for your OS or use docker:

```bash
docker run -e MYSQL_USER=petclinic -e MYSQL_PASSWORD=petclinic -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=petclinic -p 3306:3306 mysql:9.7
```

or

```bash
docker run -e POSTGRES_USER=petclinic -e POSTGRES_PASSWORD=petclinic -e POSTGRES_DB=petclinic -p 5432:5432 postgres:18.4
```

Further documentation is provided for [MySQL](https://github.com/spring-projects/spring-petclinic/blob/main/src/main/resources/db/mysql/petclinic_db_setup_mysql.txt)
and [PostgreSQL](https://github.com/spring-projects/spring-petclinic/blob/main/src/main/resources/db/postgres/petclinic_db_setup_postgres.txt).

Instead of vanilla `docker` you can also use the provided `docker-compose.yml` file to start the database containers. Each one has a service named after the Spring profile:

```bash
docker compose up mysql
```

or

```bash
docker compose up postgres
```

## Test Applications

At development time we recommend you use the test applications set up as `main()` methods in `PetClinicIntegrationTests` (using the default H2 database and also adding Spring Boot Devtools), `MySqlTestApplication` and `PostgresIntegrationTests`. These are set up so that you can run the apps in your IDE to get fast feedback and also run the same classes as integration tests against the respective database. The MySql integration tests use Testcontainers to start the database in a Docker container, and the Postgres tests use Docker Compose to do the same thing.

## Compiling the CSS

There is a `petclinic.css` in `src/main/resources/static/resources/css`. It was generated from the `petclinic.scss` source, combined with the [Bootstrap](https://getbootstrap.com/) library. If you make changes to the `scss`, or upgrade Bootstrap, you will need to re-compile the CSS resources using the Maven profile "css", i.e. `./mvnw package -P css`. There is no build profile for Gradle to compile the CSS.

## Working with Petclinic in your IDE

### Prerequisites

The following items should be installed in your system:

- Java 17 or newer (full JDK, not a JRE)
- [Git command line tool](https://help.github.com/articles/set-up-git)
- Your preferred IDE
  - Eclipse with the m2e plugin. Note: when m2e is available, there is a m2 icon in `Help -> About` dialog. If m2e is
  not there, follow the installation process [here](https://www.eclipse.org/m2e/)
  - [Spring Tools Suite](https://spring.io/tools) (STS)
  - [IntelliJ IDEA](https://www.jetbrains.com/idea/)
  - [VS Code](https://code.visualstudio.com)

### Steps

1. On the command line run:

    ```bash
    git clone https://github.com/spring-projects/spring-petclinic.git
    ```

1. Inside Eclipse or STS:

    Open the project via `File -> Import -> Maven -> Existing Maven project`, then select the root directory of the cloned repo.

    Then either build on the command line `./mvnw generate-resources` or use the Eclipse launcher (right-click on project and `Run As -> Maven install`) to generate the CSS. Run the application's main method by right-clicking on it and choosing `Run As -> Java Application`.

1. Inside IntelliJ IDEA:

    In the main menu, choose `File -> Open` and select the Petclinic [pom.xml](pom.xml). Click on the `Open` button.

    - CSS files are generated from the Maven build. You can build them on the command line `./mvnw generate-resources` or right-click on the `spring-petclinic` project then `Maven -> Generates sources and Update Folders`.

    - A run configuration named `PetClinicApplication` should have been created for you if you're using a recent Ultimate version. Otherwise, run the application by right-clicking on the `PetClinicApplication` main class and choosing `Run 'PetClinicApplication'`.

1. Navigate to the Petclinic

    Visit [http://localhost:8080](http://localhost:8080) in your browser.

## Looking for something in particular?

|Spring Boot Configuration | Class or Java property files  |
|--------------------------|---|
|The Main Class | [PetClinicApplication](https://github.com/spring-projects/spring-petclinic/blob/main/src/main/java/org/springframework/samples/petclinic/PetClinicApplication.java) |
|Properties Files | [application.properties](https://github.com/spring-projects/spring-petclinic/blob/main/src/main/resources) |
|Caching | [CacheConfiguration](https://github.com/spring-projects/spring-petclinic/blob/main/src/main/java/org/springframework/samples/petclinic/system/CacheConfiguration.java) |

## Interesting Spring Petclinic branches and forks

The Spring Petclinic "main" branch in the [spring-projects](https://github.com/spring-projects/spring-petclinic)
GitHub org is the "canonical" implementation based on Spring Boot and Thymeleaf. There are
[quite a few forks](https://spring-petclinic.github.io/docs/forks.html) in the GitHub org
[spring-petclinic](https://github.com/spring-petclinic). If you are interested in using a different technology stack to implement the Pet Clinic, please join the community there.

## Interaction with other open-source projects

One of the best parts about working on the Spring Petclinic application is that we have the opportunity to work in direct contact with many Open Source projects. We found bugs/suggested improvements on various topics such as Spring, Spring Data, Bean Validation and even Eclipse! In many cases, they've been fixed/implemented in just a few days.
Here is a list of them:

| Name | Issue |
|------|-------|
| Spring JDBC: simplify usage of NamedParameterJdbcTemplate | [SPR-10256](https://github.com/spring-projects/spring-framework/issues/14889) and [SPR-10257](https://github.com/spring-projects/spring-framework/issues/14890) |
| Bean Validation / Hibernate Validator: simplify Maven dependencies and backward compatibility |[HV-790](https://hibernate.atlassian.net/browse/HV-790) and [HV-792](https://hibernate.atlassian.net/browse/HV-792) |
| Spring Data: provide more flexibility when working with JPQL queries | [DATAJPA-292](https://github.com/spring-projects/spring-data-jpa/issues/704) |

## Contributing

The [issue tracker](https://github.com/spring-projects/spring-petclinic/issues) is the preferred channel for bug reports, feature requests and submitting pull requests.

For pull requests, editor preferences are available in the [editor config](.editorconfig) for easy use in common text editors. Read more and download plugins at <https://editorconfig.org>. All commits must include a __Signed-off-by__ trailer at the end of each commit message to indicate that the contributor agrees to the Developer Certificate of Origin.
For additional details, please refer to the blog post [Hello DCO, Goodbye CLA: Simplifying Contributions to Spring](https://spring.io/blog/2025/01/06/hello-dco-goodbye-cla-simplifying-contributions-to-spring).

## License

The Spring PetClinic sample application is released under version 2.0 of the [Apache License](https://www.apache.org/licenses/LICENSE-2.0).
