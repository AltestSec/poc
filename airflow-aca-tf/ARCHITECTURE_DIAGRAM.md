# Architecture Diagram - Private Network Setup

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Azure Subscription                                  │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                        Resource Group                                   │ │
│  │                                                                         │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │ │
│  │  │              Virtual Network (10.0.0.0/16)                        │ │ │
│  │  │                                                                   │ │ │
│  │  │  ┌─────────────────────────────────────────────────────────────┐ │ │ │
│  │  │  │  Azure Firewall Subnet (10.0.0.0/24)                        │ │ │ │
│  │  │  │                                                              │ │ │ │
│  │  │  │  ┌──────────────────────────────────────────────┐          │ │ │ │
│  │  │  │  │  Azure Firewall (Basic/Standard)             │          │ │ │ │
│  │  │  │  │  - Application Rules                         │          │ │ │ │
│  │  │  │  │  - Network Rules                             │          │ │ │ │
│  │  │  │  │  - DNS Proxy                                 │          │ │ │ │
│  │  │  │  └──────────────────────────────────────────────┘          │ │ │ │
│  │  │  │                      ↑                                      │ │ │ │
│  │  │  │                      │ All Egress Traffic                  │ │ │ │
│  │  │  └──────────────────────┼──────────────────────────────────────┘ │ │ │
│  │  │                         │                                        │ │ │
│  │  │  ┌──────────────────────┴──────────────────────────────────────┐ │ │ │
│  │  │  │  Container Apps Subnet (10.0.2.0/23)                        │ │ │ │
│  │  │  │  Delegated to: Microsoft.App/environments                   │ │ │ │
│  │  │  │                                                              │ │ │ │
│  │  │  │  ┌────────────────────────────────────────────────────────┐ │ │ │ │
│  │  │  │  │  Container Apps Environment                            │ │ │ │ │
│  │  │  │  │  - Internal Load Balancer                              │ │ │ │ │
│  │  │  │  │  - Log Analytics Integration                           │ │ │ │ │
│  │  │  │  │                                                         │ │ │ │ │
│  │  │  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │ │ │ │ │
│  │  │  │  │  │  Scheduler   │  │  Webserver   │  │   Worker     │ │ │ │ │ │
│  │  │  │  │  │  (1-2 pods)  │  │  (1 pod)     │  │  (0-10 pods) │ │ │ │ │ │
│  │  │  │  │  └──────────────┘  └──────────────┘  └──────────────┘ │ │ │ │ │
│  │  │  │  │                                                         │ │ │ │ │
│  │  │  │  │  ┌──────────────┐  ┌──────────────────────────────┐   │ │ │ │ │
│  │  │  │  │  │  Triggerer   │  │  ETL Runner Job              │   │ │ │ │ │
│  │  │  │  │  │  (1 pod)     │  │  (Manual Trigger)            │   │ │ │ │ │
│  │  │  │  │  └──────────────┘  └──────────────────────────────┘   │ │ │ │ │
│  │  │  │  └────────────────────────────────────────────────────────┘ │ │ │ │
│  │  │  └──────────────────────────────────────────────────────────────┘ │ │ │
│  │  │                                                                    │ │ │
│  │  │  ┌──────────────────────────────────────────────────────────────┐ │ │ │
│  │  │  │  Private Endpoints Subnet (10.0.4.0/24)                      │ │ │ │
│  │  │  │                                                               │ │ │ │
│  │  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐            │ │ │ │
│  │  │  │  │ ACR PE     │  │ Blob PE    │  │ File PE    │            │ │ │ │
│  │  │  │  │ 10.0.4.x   │  │ 10.0.4.y   │  │ 10.0.4.z   │            │ │ │ │
│  │  │  │  └────────────┘  └────────────┘  └────────────┘            │ │ │ │
│  │  │  └──────────────────────────────────────────────────────────────┘ │ │ │
│  │  │                                                                    │ │ │
│  │  │  ┌──────────────────────────────────────────────────────────────┐ │ │ │
│  │  │  │  PostgreSQL Subnet (10.0.5.0/24)                             │ │ │ │
│  │  │  │  Delegated to: Microsoft.DBforPostgreSQL/flexibleServers     │ │ │ │
│  │  │  │                                                               │ │ │ │
│  │  │  │  ┌────────────────────────────────────────────────────────┐  │ │ │ │
│  │  │  │  │  PostgreSQL Flexible Server                            │  │ │ │ │
│  │  │  │  │  - Private DNS Integration                             │  │ │ │ │
│  │  │  │  │  - No Public Access                                    │  │ │ │ │
│  │  │  │  └────────────────────────────────────────────────────────┘  │ │ │ │
│  │  │  └──────────────────────────────────────────────────────────────┘ │ │ │
│  │  │                                                                    │ │ │
│  │  └────────────────────────────────────────────────────────────────────┘ │ │
│  │                                                                         │ │
│  │  ┌────────────────────────────────────────────────────────────────┐   │ │
│  │  │  Private DNS Zones                                              │   │ │
│  │  │  - privatelink.azurecr.io                                       │   │ │
│  │  │  - privatelink.blob.core.windows.net                            │   │ │
│  │  │  - privatelink.file.core.windows.net                            │   │ │
│  │  │  - privatelink.postgres.database.azure.com                      │   │ │
│  │  └────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                         │ │
│  │  ┌────────────────────────────────────────────────────────────────┐   │ │
│  │  │  Other Resources (Not in VNet)                                  │   │ │
│  │  │  - Azure Container Registry (Premium, Private)                  │   │ │
│  │  │  - Storage Account (Private)                                    │   │ │
│  │  │  - Redis Cache                                                  │   │ │
│  │  │  - Key Vault                                                    │   │ │
│  │  │  - Log Analytics Workspace                                      │   │ │
│  │  │  - Managed Identities (4)                                       │   │ │
│  │  └────────────────────────────────────────────────────────────────┘   │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Traffic Flow Diagram

### Ingress Traffic (Webserver Access)

```
User
  │
  ├─ Option 1: Azure Container Apps Tunnel
  │    └─> az containerapp tunnel --port 8080:8080
  │         └─> Webserver (Internal)
  │
  └─ Option 2: Jump Box / Bastion (Future)
       └─> VNet
            └─> Webserver (Internal)
```

### Egress Traffic (All Container Apps)

```
Container App
  │
  ├─> User Defined Route (0.0.0.0/0)
  │    └─> Azure Firewall (10.0.0.x)
  │         │
  │         ├─> Application Rules Check
  │         │    ├─ Allowed: *.azurecr.io, pypi.org, etc.
  │         │    └─ Blocked: *.google.com, etc.
  │         │
  │         └─> Network Rules Check
  │              └─ DNS (UDP 53)
  │
  └─> Internet (if allowed by firewall)
```

### Private Endpoint Resolution

```
Container App
  │
  ├─> DNS Query: myacr.azurecr.io
  │    └─> Azure Firewall DNS Proxy
  │         └─> Private DNS Zone: privatelink.azurecr.io
  │              └─> Returns: 10.0.4.x (Private IP)
  │
  └─> Connect to 10.0.4.x
       └─> Private Endpoint
            └─> Azure Container Registry
```

## Security Layers

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 7: Application Security                               │
│ - Managed Identity Authentication                           │
│ - RBAC Authorization                                         │
│ - Key Vault for Secrets                                     │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 4-7: Firewall Rules                                   │
│ - Application Rules (FQDN filtering)                        │
│ - Network Rules (Port/Protocol filtering)                   │
│ - DNS Proxy                                                 │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: Network Security                                   │
│ - User Defined Routes                                       │
│ - Network Segmentation (Subnets)                            │
│ - Private Endpoints                                         │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: Data Link                                          │
│ - Virtual Network Isolation                                 │
│ - Subnet Delegation                                         │
└─────────────────────────────────────────────────────────────┘
```

## Component Interaction

```
┌──────────────┐
│   Scheduler  │
└──────┬───────┘
       │
       ├─> PostgreSQL (via private network)
       ├─> Redis (via private network)
       ├─> Storage File Share (via private endpoint) - Read DAGs
       └─> Trigger Tasks
            │
            ↓
       ┌──────────┐
       │  Worker  │
       └────┬─────┘
            │
            ├─> PostgreSQL (via private network)
            ├─> Redis (via private network)
            ├─> Storage Blob (via private endpoint) - Write Logs
            └─> Execute Tasks
                 │
                 ├─> Start ETL Job (via Azure API)
                 │    └─> ETL Runner Container Job
                 │         └─> Egress via Firewall
                 │
                 └─> Other Operations

┌──────────────┐
│  Webserver   │
└──────┬───────┘
       │
       ├─> PostgreSQL (via private network)
       ├─> Storage File Share (via private endpoint) - Read DAGs
       └─> Serve UI (internal ingress only)

┌──────────────┐
│  Triggerer   │
└──────┬───────┘
       │
       ├─> PostgreSQL (via private network)
       ├─> Redis (via private network)
       └─> Handle Deferred Tasks
```

## Deployment Flow

```
1. Network Setup
   ├─> Create VNet
   ├─> Create Subnets
   ├─> Deploy Azure Firewall
   ├─> Configure UDR
   └─> Create Private DNS Zones

2. Core Services
   ├─> Deploy ACR (with private endpoint)
   ├─> Deploy Storage (with private endpoints)
   ├─> Deploy PostgreSQL (in delegated subnet)
   ├─> Deploy Redis
   ├─> Deploy Key Vault
   └─> Deploy Log Analytics

3. Identity & Access
   ├─> Create Managed Identities
   └─> Assign RBAC Roles

4. Container Apps
   ├─> Create ACA Environment (VNet-integrated)
   ├─> Deploy Scheduler
   ├─> Deploy Webserver
   ├─> Deploy Worker
   ├─> Deploy Triggerer
   └─> Create ETL Job

5. Validation
   ├─> Test Network Connectivity
   ├─> Test Private Endpoints
   ├─> Test Firewall Rules
   └─> Run Security Tests
```

## Monitoring & Logging

```
┌─────────────────────────────────────────────────────────────┐
│                   Log Analytics Workspace                    │
│                                                              │
│  ┌────────────────┐  ┌────────────────┐  ┌───────────────┐ │
│  │ Firewall Logs  │  │ Container Logs │  │ Diagnostic    │ │
│  │ - App Rules    │  │ - Scheduler    │  │ Settings      │ │
│  │ - Net Rules    │  │ - Webserver    │  │ - ACR         │ │
│  │ - DNS Proxy    │  │ - Worker       │  │ - Storage     │ │
│  └────────────────┘  └────────────────┘  └───────────────┘ │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Queries & Alerts                                     │   │
│  │  - Failed firewall rules                             │   │
│  │  - Container startup failures                        │   │
│  │  - High egress traffic                               │   │
│  │  - Security anomalies                                │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Legend

```
┌─────────┐
│ Box     │  = Component or Resource
└─────────┘

───────────  = Network Connection

─────>       = Traffic Flow

PE           = Private Endpoint

UDR          = User Defined Route
```
