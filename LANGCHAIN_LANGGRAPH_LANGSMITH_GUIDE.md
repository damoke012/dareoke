# Complete Guide to LangChain, LangGraph, and LangSmith

## Table of Contents
1. [LangChain Framework](#langchain-framework)
2. [LangGraph - State Machine Agents](#langgraph---state-machine-agents)
3. [LangSmith - Observability & Debugging](#langsmith---observability--debugging)
4. [Integration & Best Practices](#integration--best-practices)
5. [Hands-On Examples](#hands-on-examples)

---

# LangChain Framework

## Overview

LangChain is an open-source Python framework that simplifies every step of the LLM app lifecycle. It's the easiest way to start building agents and applications powered by LLMs - with under 10 lines of code, you can connect to OpenAI, Anthropic, Google, and more.

### Core Purpose
- Simplify building production-ready LLM applications
- Provide modular, composable components
- Enable complex agentic workflows
- Support the complete LLM application lifecycle

---

## Architecture Components

LangChain is organized into several key packages:

### 1. **langchain-core**
Base abstractions for different components and ways to compose them together. Core interfaces for:
- Chat models
- Vector stores
- Tools
- Embeddings
- Document loaders

### 2. **Integration Packages**
For each supported LLM provider or external tool:
- `langchain-openai` - OpenAI integration
- `langchain-anthropic` - Anthropic Claude integration
- `langchain-google` - Google Gemini integration
- `langchain-redis` - Redis vector store
- And 100+ more integrations

### 3. **Main langchain Package**
Contains chains and retrieval strategies that make up an application's cognitive architecture:
- Sequential chains
- Retrieval-Augmented Generation (RAG)
- Question-Answering systems
- Summarization pipelines

### 4. **langchain-community**
Third-party integrations maintained by the LangChain community for various components.

### 5. **LangGraph**
Extension for building robust and stateful multi-actor applications with LLMs by modeling steps as edges and nodes in a graph.

---

## Key Design Principles

### 1. Modularity
Every component works independently or as part of larger systems. You can use:
- Conversation memory without document loaders
- Vector stores without LLM calls
- Tools without agents

### 2. Composability
Components work together seamlessly:
```python
from langchain_openai import ChatOpenAI
from langchain.prompts import ChatPromptTemplate
from langchain.schema.output_parser import StrOutputParser

# Compose components into a chain
llm = ChatOpenAI(model="gpt-4")
prompt = ChatPromptTemplate.from_template("Tell me about {topic}")
chain = prompt | llm | StrOutputParser()

result = chain.invoke({"topic": "quantum computing"})
```

---

## Main Building Blocks

### 1. **Models**
Interface with different LLM providers:

```python
from langchain_openai import ChatOpenAI
from langchain_anthropic import ChatAnthropic

# OpenAI
openai_llm = ChatOpenAI(model="gpt-4")

# Anthropic Claude
claude_llm = ChatAnthropic(model="claude-3-5-sonnet-20241022")
```

### 2. **Prompts**
Create and manage prompt templates:

```python
from langchain.prompts import PromptTemplate

template = """You are a helpful assistant.
User question: {question}
Answer:"""

prompt = PromptTemplate(template=template, input_variables=["question"])
```

### 3. **Chains**
Series of steps where each step feeds output to the next:

```python
from langchain.chains import LLMChain

chain = LLMChain(llm=llm, prompt=prompt)
result = chain.invoke({"question": "What is RAG?"})
```

### 4. **Memory**
Maintain context over interactions:

```python
from langchain.memory import ConversationBufferMemory

memory = ConversationBufferMemory()
memory.save_context({"input": "Hi"}, {"output": "Hello!"})
```

### 5. **Agents**
Decision-making entities that use tools:

```python
from langchain.agents import create_openai_functions_agent
from langchain.tools import Tool

tools = [
    Tool(name="Calculator", func=lambda x: eval(x), description="Does math")
]

agent = create_openai_functions_agent(llm, tools, prompt)
```

### 6. **Retrieval (RAG)**
Retrieve relevant documents to augment LLM responses:

```python
from langchain_community.vectorstores import Chroma
from langchain_openai import OpenAIEmbeddings
from langchain.chains import RetrievalQA

# Create vector store
vectorstore = Chroma.from_documents(documents, OpenAIEmbeddings())

# Create RAG chain
qa_chain = RetrievalQA.from_chain_type(
    llm=llm,
    retriever=vectorstore.as_retriever()
)
```

---

## Common Use Cases

| Use Case | Components Used |
|----------|----------------|
| **Chatbots** | ChatModels + Memory + Prompts |
| **RAG Systems** | Embeddings + VectorStores + Retrieval + LLM |
| **Document Q&A** | Document Loaders + Splitters + VectorStores + QA Chain |
| **Agents** | Tools + Agent Executor + LLM |
| **Summarization** | Document Loaders + Summarization Chain |
| **Code Generation** | LLM + Code-specific prompts + Validation tools |

---

# LangGraph - State Machine Agents

## Overview

LangGraph was introduced in early 2024 as a separate library built on top of LangChain to address limitations in complex agentic workflows involving loops or cycles. It's a graph-based framework for building AI agents that can reason, plan, and act through interconnected steps.

### Why LangGraph?

Traditional chains are **linear** - they go from A → B → C. LangGraph enables:
- **Cyclical workflows** - loops and feedback mechanisms
- **Branching logic** - conditional paths based on state
- **Multi-agent systems** - multiple agents collaborating
- **State management** - automatic handling of shared memory

---

## Core Concepts

### 1. State Machines

LangGraph builds upon Finite State Machines (FSMs) to model AI agent interactions. In an agentic state machine:
- **States** are independent agent nodes
- **Transitions** aren't hardcoded - agents decide which transition to take
- **Autonomy** - agents choose paths based on current state and context

### 2. State

The **state** is a shared memory object that flows through the graph:
```python
from typing import TypedDict

class AgentState(TypedDict):
    messages: list
    next_step: str
    intermediate_results: dict
    decision_history: list
```

LangGraph manages this state automatically as it flows between nodes.

### 3. Graphs

Graphs organize workflows with:
- **Nodes** - Steps in workflow (LLM calls, tools, functions)
- **Edges** - Connections between nodes
- **Conditional edges** - Dynamic routing based on state

```python
from langgraph.graph import StateGraph, END

workflow = StateGraph(AgentState)

# Add nodes
workflow.add_node("agent", agent_node)
workflow.add_node("tool", tool_node)

# Add edges
workflow.add_edge("agent", "tool")
workflow.add_conditional_edges(
    "tool",
    should_continue,  # Function that returns next node
    {
        "continue": "agent",
        "end": END
    }
)

# Set entry point
workflow.set_entry_point("agent")

# Compile
app = workflow.compile()
```

---

## LangGraph vs LangChain

| Feature | LangChain | LangGraph |
|---------|-----------|-----------|
| **Workflow** | Linear chains | Cyclical graphs |
| **Loops** | Limited | Native support |
| **State** | Manual management | Automatic |
| **Complexity** | Simple → Medium | Medium → Complex |
| **Use Case** | RAG, chatbots | Multi-agent, planning |

**When to use LangGraph:**
- Multi-step reasoning with feedback loops
- Agents that need to retry or backtrack
- Multiple agents collaborating
- Complex decision trees

**When to use LangChain:**
- Simple RAG applications
- Linear chatbots
- Document Q&A
- One-shot summarization

---

## Building a LangGraph Agent

### Example: Research Agent with Feedback Loop

```python
from langgraph.graph import StateGraph, END
from typing import TypedDict, Annotated
import operator

# Define state
class ResearchState(TypedDict):
    query: str
    context: Annotated[list, operator.add]
    answer: str
    iterations: int

# Define nodes
def search_node(state: ResearchState):
    """Search for relevant information"""
    # Simulate search
    results = search_api(state["query"])
    return {"context": results, "iterations": state["iterations"] + 1}

def answer_node(state: ResearchState):
    """Generate answer from context"""
    llm = ChatOpenAI()
    answer = llm.invoke(f"Context: {state['context']}\nQuestion: {state['query']}")
    return {"answer": answer}

def should_continue(state: ResearchState):
    """Decide if we need more context"""
    if len(state["context"]) < 3 and state["iterations"] < 3:
        return "search"
    return "answer"

# Build graph
workflow = StateGraph(ResearchState)
workflow.add_node("search", search_node)
workflow.add_node("answer", answer_node)

workflow.set_entry_point("search")
workflow.add_conditional_edges(
    "search",
    should_continue,
    {
        "search": "search",  # Loop back for more context
        "answer": "answer"
    }
)
workflow.add_edge("answer", END)

app = workflow.compile()

# Run
result = app.invoke({
    "query": "What is quantum computing?",
    "context": [],
    "answer": "",
    "iterations": 0
})
```

---

## Advanced LangGraph Patterns

### 1. Multi-Agent Collaboration

```python
# Multiple agents working together
workflow.add_node("researcher", research_agent)
workflow.add_node("writer", writing_agent)
workflow.add_node("reviewer", review_agent)

workflow.add_edge("researcher", "writer")
workflow.add_edge("writer", "reviewer")
workflow.add_conditional_edges(
    "reviewer",
    lambda s: "writer" if s["needs_revision"] else END
)
```

### 2. Human-in-the-Loop

```python
from langgraph.checkpoint.memory import MemorySaver

memory = MemorySaver()
app = workflow.compile(checkpointer=memory, interrupt_before=["human_review"])

# Agent pauses for human input
result = app.invoke(state, thread_id="123")
# Human reviews, provides feedback
result = app.invoke(state, thread_id="123")  # Continues from checkpoint
```

### 3. Parallel Processing

```python
workflow.add_node("task1", task1_node)
workflow.add_node("task2", task2_node)
workflow.add_node("combine", combine_results)

workflow.add_edge(START, "task1")
workflow.add_edge(START, "task2")
workflow.add_edge(["task1", "task2"], "combine")  # Wait for both
```

---

# LangSmith - Observability & Debugging

## Overview

LangSmith is a platform by LangChain that provides LLM-native observability, offering meaningful insights throughout all stages of application development - from prototyping to production.

### Why LangSmith?

LLMs are **non-deterministic** by nature, producing unexpected results that make debugging tricky. LangSmith helps:
- Quickly debug non-deterministic behavior
- Understand what agents are doing step-by-step
- Fix issues and improve latency
- Enhance response quality

---

## Key Features

### 1. **Tracing**

Visualize every step of LLM execution:
```
User Query
  ├─ Prompt Template
  ├─ LLM Call (GPT-4)
  │   ├─ Input tokens: 150
  │   ├─ Output tokens: 200
  │   └─ Latency: 2.3s
  ├─ Vector Store Search
  │   ├─ Query embedding
  │   ├─ Similarity search
  │   └─ Top 5 results
  └─ Final Response
```

### 2. **Dashboard Interface**

- **Overview**: Recent runs, statistics, success rates
- **Detailed View**: Individual executions with inputs, outputs, metadata
- **Step-by-Step Inspection**: Drill down into chains, agents, LLM calls
- **Token Usage**: Track costs across runs

### 3. **Debugging Tools**

- Inspect intermediate outputs
- View execution time per step
- Compare different runs
- Identify bottlenecks

### 4. **Evaluation & Testing**

- Create test datasets
- Run evaluations on prompts
- A/B test different approaches
- Collect user feedback

---

## Setup & Integration

### Quick Start (LangChain/LangGraph)

Enable tracing with environment variables:

```bash
export LANGCHAIN_TRACING_V2=true
export LANGCHAIN_API_KEY="your-api-key"
export LANGCHAIN_PROJECT="my-project"
```

That's it! LangChain automatically sends traces to LangSmith.

### Manual Tracing (Any Application)

```python
from langsmith import traceable

@traceable
def my_llm_function(query: str):
    # Your LLM logic
    response = llm.invoke(query)
    return response
```

---

## OpenTelemetry Integration (2025)

LangSmith now supports end-to-end OpenTelemetry for standardized tracing:

```python
from langsmith import LangSmithTracer
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("llm_call"):
    result = llm.invoke(prompt)
```

Benefits:
- Send traces to LangSmith or other observability platforms
- Standardize tracing across your entire stack
- Integrate with existing monitoring tools

---

## Production Features

### 1. Monitoring Charts
- Track latency over time
- Monitor token usage and costs
- Success/failure rates
- User satisfaction scores

### 2. Feedback Collection
```python
from langsmith import Client

client = Client()
client.create_feedback(
    run_id=run.id,
    key="user_score",
    score=0.8,
    comment="Good response but could be more concise"
)
```

### 3. Dataset Management
Create datasets for testing:
```python
dataset = client.create_dataset("qa-pairs")
client.create_example(
    dataset_id=dataset.id,
    inputs={"question": "What is RAG?"},
    outputs={"answer": "Retrieval-Augmented Generation..."}
)
```

---

# Integration & Best Practices

## Complete Stack Example

```python
import os
from langchain_openai import ChatOpenAI
from langchain.prompts import ChatPromptTemplate
from langgraph.graph import StateGraph, END
from langsmith import traceable

# LangSmith setup
os.environ["LANGCHAIN_TRACING_V2"] = "true"
os.environ["LANGCHAIN_PROJECT"] = "production-agent"

# LangChain components
llm = ChatOpenAI(model="gpt-4")
prompt = ChatPromptTemplate.from_template("Answer: {question}")

# LangGraph workflow
class State(TypedDict):
    question: str
    answer: str

@traceable  # LangSmith tracing
def agent_node(state: State):
    chain = prompt | llm
    answer = chain.invoke({"question": state["question"]})
    return {"answer": answer.content}

workflow = StateGraph(State)
workflow.add_node("agent", agent_node)
workflow.set_entry_point("agent")
workflow.add_edge("agent", END)

app = workflow.compile()

# Run with full observability
result = app.invoke({"question": "What is LangChain?"})
```

---

## Best Practices

### 1. **Start Simple, Scale Up**
- Begin with LangChain for basic RAG
- Add LangGraph when you need loops/multi-agent
- Use LangSmith from day 1 for debugging

### 2. **State Management**
```python
# Good: Structured state
class State(TypedDict):
    messages: list[str]
    context: dict
    metadata: dict

# Bad: Unstructured state
state = {}  # Hard to debug
```

### 3. **Error Handling**
```python
from langgraph.errors import GraphRecursionError

try:
    result = app.invoke(state, recursion_limit=10)
except GraphRecursionError:
    # Handle infinite loops
    pass
```

### 4. **Observability**
- Name your nodes clearly
- Add metadata to traces
- Create test datasets
- Monitor production metrics

### 5. **Cost Optimization**
- Cache embeddings
- Use cheaper models for simple tasks
- Implement early stopping
- Track token usage with LangSmith

---

# Hands-On Examples

## Example 1: RAG System with LangChain

```python
from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain_community.vectorstores import Chroma
from langchain.chains import RetrievalQA
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import TextLoader

# Load documents
loader = TextLoader("data.txt")
documents = loader.load()

# Split into chunks
splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
chunks = splitter.split_documents(documents)

# Create embeddings and vector store
embeddings = OpenAIEmbeddings()
vectorstore = Chroma.from_documents(chunks, embeddings)

# Create QA chain
llm = ChatOpenAI(model="gpt-4")
qa_chain = RetrievalQA.from_chain_type(
    llm=llm,
    chain_type="stuff",
    retriever=vectorstore.as_retriever(search_kwargs={"k": 3})
)

# Query
result = qa_chain.invoke({"query": "What are the key findings?"})
print(result["result"])
```

## Example 2: Multi-Agent System with LangGraph

```python
from langgraph.graph import StateGraph, END
from typing import TypedDict, Literal

class ResearchState(TypedDict):
    topic: str
    research_data: list
    draft: str
    final_report: str

def researcher_agent(state: ResearchState):
    """Research the topic"""
    llm = ChatOpenAI()
    research = llm.invoke(f"Research: {state['topic']}")
    return {"research_data": [research.content]}

def writer_agent(state: ResearchState):
    """Write draft from research"""
    llm = ChatOpenAI()
    draft = llm.invoke(f"Write report from: {state['research_data']}")
    return {"draft": draft.content}

def editor_agent(state: ResearchState):
    """Edit and finalize"""
    llm = ChatOpenAI()
    final = llm.invoke(f"Edit and improve: {state['draft']}")
    return {"final_report": final.content}

# Build workflow
workflow = StateGraph(ResearchState)
workflow.add_node("researcher", researcher_agent)
workflow.add_node("writer", writer_agent)
workflow.add_node("editor", editor_agent)

workflow.set_entry_point("researcher")
workflow.add_edge("researcher", "writer")
workflow.add_edge("writer", "editor")
workflow.add_edge("editor", END)

app = workflow.compile()

# Run
result = app.invoke({"topic": "AI in Healthcare", "research_data": [], "draft": "", "final_report": ""})
print(result["final_report"])
```

## Example 3: Agent with Tools and Memory

```python
from langchain.agents import create_openai_tools_agent, AgentExecutor
from langchain.tools import Tool
from langchain.memory import ConversationBufferMemory
from langchain.prompts import MessagesPlaceholder

# Define tools
def calculator(expression: str) -> str:
    """Calculate math expressions"""
    return str(eval(expression))

def search(query: str) -> str:
    """Search the web"""
    return f"Results for: {query}"

tools = [
    Tool(name="Calculator", func=calculator, description="Does math"),
    Tool(name="Search", func=search, description="Searches web")
]

# Setup memory
memory = ConversationBufferMemory(memory_key="chat_history", return_messages=True)

# Create agent
llm = ChatOpenAI(model="gpt-4")
prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    MessagesPlaceholder(variable_name="chat_history"),
    ("human", "{input}"),
    MessagesPlaceholder(variable_name="agent_scratchpad")
])

agent = create_openai_tools_agent(llm, tools, prompt)
executor = AgentExecutor(agent=agent, tools=tools, memory=memory, verbose=True)

# Run
result = executor.invoke({"input": "What is 25 * 4?"})
print(result["output"])
```

---

## Resources & Documentation

### LangChain
- [Architecture Documentation](https://python.langchain.com/docs/concepts/architecture/)
- [LangChain Tutorial (2025)](https://dev.to/fonyuygita/the-complete-beginners-guide-to-langchain-why-every-developer-needs-this-framework-in-2025part-1-2d55)
- [DigitalOcean Guide](https://www.digitalocean.com/community/conceptual-articles/langchain-framework-explained)
- [GeeksforGeeks Introduction](https://www.geeksforgeeks.org/artificial-intelligence/introduction-to-langchain/)

### LangGraph
- [LangGraph Official Site](https://www.langchain.com/langgraph)
- [State Machines Production Guide](https://dev.to/jamesli/langgraph-state-machines-managing-complex-agent-task-flows-in-production-36f4)
- [IBM Tutorial - Agentic Workflows](https://www.ibm.com/think/tutorials/build-agentic-workflows-langgraph-granite)
- [Real Python - LangGraph Tutorial](https://realpython.com/langgraph-python/)
- [DataCamp Hands-On Tutorial](https://www.datacamp.com/tutorial/langgraph-agents)

### LangSmith
- [LangSmith Observability](https://www.langchain.com/langsmith)
- [Ultimate LangSmith Guide 2025](https://www.analyticsvidhya.com/blog/2024/07/ultimate-langsmith-guide/)
- [Tracing Quickstart](https://docs.langchain.com/langsmith/observability-quickstart)
- [OpenTelemetry Integration](https://blog.langchain.com/end-to-end-opentelemetry-langsmith/)
- [LangSmith Evaluation Guide](https://www.analyticsvidhya.com/blog/2025/11/evaluating-llms-with-langsmith/)

---

## Summary

| Tool | Purpose | When to Use |
|------|---------|-------------|
| **LangChain** | Build LLM applications | RAG, chatbots, Q&A systems |
| **LangGraph** | Complex workflows | Multi-agent, loops, state machines |
| **LangSmith** | Observability | Debug, monitor, evaluate |

**Start here:**
1. Learn LangChain basics (prompts, chains, RAG)
2. Add LangGraph for complex workflows
3. Use LangSmith for debugging and production monitoring

**Next steps:**
- Build a simple RAG chatbot with LangChain
- Create a multi-agent research system with LangGraph
- Deploy to production with LangSmith observability
