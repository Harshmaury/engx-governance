# Workflow Philosophy

The design philosophy governing how this developer platform is built
and how it evolves over time.

---

## Core Idea

The workstation is a system, not a collection of tools.

Tools are components. Components are orchestrated. The developer
interacts with a unified platform rather than running individual
commands manually.

---

## The Ten Constraints

These constraints govern every architectural decision on this platform.
A proposed change that violates any of these requires explicit justification
and an ADR before proceeding.

### 1. No Hard-Coded Project Structures

The architecture never assumes specific projects will permanently exist.
Projects may change, be replaced, be removed, or be rewritten.
Platform components treat projects as dynamic, not fixed.

### 2. Architecture Must Be Capability-Based

System descriptions are organised by capabilities, not implementations.
The three stable capability domains are:

    Control — Nexus
    Knowledge — Atlas
    Execution — Forge

Specific projects implementing these capabilities may change over time.
The capability domains do not change.

### 3. Workflow Must Be Decoupled From Implementation

Workflows describe processes and responsibilities, not specific tools.
A workflow says what happens. It does not say which binary runs it.

### 4. Modular and Replaceable Components

Every subsystem is designed so it can be replaced without requiring
major changes to other components. Modules evolve, may be rewritten,
and may disappear. The system remains functional.

### 5. Independent Project Principle

Each project operates as an independent application.
Integration occurs through APIs, events, and CLI interfaces.
Projects never rely on internal implementation details of other projects.

### 6. Interface Contracts Over Direct Dependencies

Communication between components relies on interfaces, not coupling.
Preferred mechanisms: REST APIs, event bus, command interfaces.
Direct internal package dependencies between separate projects are prohibited.

### 7. Documentation Must Be Update-Friendly

Architecture documents are structured so updates affect only a small section.
Monolithic documents that require large rewrites to change one thing
are a design failure.

### 8. Future-Proof Design

New tools will appear. Languages may change. Infrastructure providers
may change. Execution environments may change.
Architecture supports extension without redesign.

### 9. Environment-Agnostic Descriptions

Descriptions avoid assuming specific infrastructure unless necessary.
No component says "Docker must run all workloads."
Components say "a container runtime provider executes workloads."

### 10. Separation of Workflow and Architecture

Workflow definitions describe how work is performed.
Architecture defines system structure.
The two are loosely connected and evolve independently.

---

## The Platform Model

The workstation becomes a programmable development platform where:

- development tools are orchestrated rather than manually executed
- workflows are automated and reproducible
- environments are programmable and controlled by software
- projects remain independent but integrate into a larger system
- the developer interacts through a unified command interface

---

## Tools Become Components

Individual tools — compilers, container runtimes, scripts — are not
standalone utilities. They are components within the platform that
can be orchestrated and combined.

---

## Workflows Replace Manual Commands

Instead of:
```
docker build
docker run
kubectl apply
```

The developer uses:
```
engx run deploy nexus
```

Forge plans and executes the required steps. The developer expresses
intent. The platform handles coordination.

---

## The Platform Must Grow With the Developer

The system supports continuous evolution. New projects, new languages,
new tools, and new workflows are added without architectural redesign.
The capability domains are stable. The implementations within them evolve.
