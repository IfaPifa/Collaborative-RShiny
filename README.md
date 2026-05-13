**Collaborative-RShiny (ShinySwarm)**

This document contains the project files for my Master's Thesis in Software Engineering at the University of Amsterdam (UvA). The primary goal of this project is to build, evaluate, and benchmark a collaborative, cloud-based, microservice-oriented environment for RShiny web applications, which I have named ShinySwarm.

**Thesis Objectives and Evaluation**

The core of this research focuses on benchmarking different system architectures to determine the most effective way to deploy collaborative RShiny applications. The final results will evaluate these setups based on the following metrics:

- _Latency_: Measuring the response time of collaborative interactions and state updates.
- _Speed_: Overall application performance, load times, and throughput.
- _Data Loss_: Ensuring accurate synchronization and robust state persistence between multiple users.
- _Cross-Contamination_: Testing for state leakage or concurrency issues between parallel user sessions.

**System Architectures**

To properly evaluate the metrics above, this repository isolates different architectural approaches:

- **_REST API Architecture (Thesis-Project-Final-RESTAPI directory)_**: Utilizes plumber to run R backend services as RESTful APIs, orchestrated alongside a Java Spring Boot backend, Angular frontend, Redis cache for the State Vault, and a PostgreSQL database.
- **_Event-Driven Architecture (Thesis-Project-Final-Kafka directory)_**: Utilizes Apache Kafka as a message broker for handling real-time state synchronization and microservice communication.
- **_Monolithic Baseline (whole_apps directory)_**: Standard, monolithic RShiny applications used to establish a baseline for speed, latency, and resource consumption comparisons against the microservice setups.

**Getting Started for Local Execution**

For local development, testing, and debugging, Docker Compose is used to spin up the entire ecosystem seamlessly, serving as a straightforward local executable.

To run a specific architecture locally, navigate to the desired architecture directory in your terminal. Then, build and start the containers in detached mode using the command:

**_docker-compose up --build -d_**

Depending on the architecture, the ecosystem will spin up the core services. For example, the REST API setup includes an Angular Frontend on Port 4200, a Java Spring Boot Backend on Port 8085, a PostgreSQL Database on Port 5432, a Redis State Vault on Port 6379, an Nginx Proxy, and dedicated RShiny Services for various applications like the Calculator, Visual Analytics, Data Exchange, Monte Carlo, Map, and Machine Learning apps.

To tear down the environment and stop all running containers, use the command:

**_docker-compose down_**

**Deployment for Cluster and Production**

For the final thesis results and true distributed testing, the application is designed to be deployed on Kubernetes managed via Rancher. Full deployment manifests, such as full-rancher-deployment.yaml, are provided in the respective architecture folders to orchestrate the microservices across the cluster.

Author: Iva Gunjaca

Master of Software Engineering, University of Amsterdam
