# 领域驱动设计 (Domain-Driven Design, DDD)

## 一、什么是 DDD？

领域驱动设计（DDD）是由 Eric Evans 在 2003 年《领域驱动设计：软件核心复杂性应对之道》中提出的一套软件设计方法论。其核心思想是：

> **让软件模型与业务领域模型高度一致，用领域语言贯穿代码与沟通。**

DDD 不是一个框架，而是一种思维方式与设计哲学，适用于解决**复杂业务系统**的建模问题。

---

## 二、核心概念

### 1. 通用语言（Ubiquitous Language）

团队（开发 + 业务）统一使用同一套术语，消除理解偏差。代码中的类名、方法名应直接反映业务语言。

```
❌ 避免：processData(), handleRequest(), doSomething()
✅ 推荐：submitOrder(), approveRefund(), activateAccount()
```

---

### 2. 限界上下文（Bounded Context）

将大型系统拆分为多个独立的上下文边界，每个上下文内部有自己独立的模型和语言。

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   订单上下文      │    │   库存上下文      │    │   支付上下文      │
│  Order          │    │  Inventory      │    │  Payment        │
│  OrderItem      │    │  Stock          │    │  Transaction    │
│  Customer(简化)  │    │  Product        │    │  Account        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

同一个概念（如"商品"）在不同上下文中含义和属性可以不同。

---

### 3. 战略设计（Strategic Design）

上下文映射（Context Mapping）关系：

| 关系模式 | 说明 |
|---------|------|
| **防腐层 (ACL)** | 隔离外部模型，防止污染内部领域 |
| **开放主机服务 (OHS)** | 提供标准协议供他人集成 |
| **共享内核 (Shared Kernel)** | 两个上下文共享部分模型 |
| **顺从者 (Conformist)** | 完全跟随上游模型 |
| **客户/供应商 (Customer/Supplier)** | 上下游协商接口 |

---

### 4. 战术设计（Tactical Design）

#### 4.1 实体（Entity）

有唯一标识、有生命周期，两个实体相等靠 ID 判断。

```java
// 实体的核心：唯一标识
public class Order {
    private final OrderId id;        // 唯一标识
    private OrderStatus status;
    private List<OrderItem> items;
    
    // 业务行为放在实体内，而非贫血模型的 Service
    public void submit() {
        if (items.isEmpty()) throw new DomainException("订单不能为空");
        this.status = OrderStatus.SUBMITTED;
        DomainEventPublisher.publish(new OrderSubmittedEvent(this.id));
    }
}
```

#### 4.2 值对象（Value Object）

无唯一标识，不可变，相等靠属性值判断。

```java
// 值对象：不可变、无 ID、相等靠值
@Value  // Lombok 不可变注解
public final class Money {
    private final BigDecimal amount;
    private final Currency currency;
    
    public Money add(Money other) {
        if (!this.currency.equals(other.currency))
            throw new DomainException("货币类型不一致");
        return new Money(this.amount.add(other.amount), this.currency);
    }
}

@Value
public final class Address {
    private final String province;
    private final String city;
    private final String street;
    private final String zipCode;
}
```

#### 4.3 聚合与聚合根（Aggregate & Aggregate Root）

聚合是一组强一致性的对象集合，聚合根是唯一入口，保证聚合内部的不变性。

```
┌──────────────────────────────────┐
│         Order (聚合根)            │
│  ┌────────────┐  ┌────────────┐  │
│  │ OrderItem  │  │ Discount   │  │
│  └────────────┘  └────────────┘  │
└──────────────────────────────────┘
外部只能通过 Order 操作 OrderItem，不能直接持有 OrderItem 引用
```

**聚合设计原则：**
- 聚合内强一致性，聚合间最终一致性
- 聚合尽量小（避免大聚合）
- 通过 ID 引用其他聚合，不直接持有对象引用

```java
public class Order {  // 聚合根
    private OrderId id;
    private CustomerId customerId;  // ✅ 用 ID 引用，不直接持有 Customer 对象
    private List<OrderItem> items = new ArrayList<>();
    private Money totalAmount;
    
    public void addItem(ProductId productId, int quantity, Money unitPrice) {
        // 聚合根保护不变性规则
        if (items.size() >= 50) throw new DomainException("订单明细不能超过50条");
        items.add(new OrderItem(productId, quantity, unitPrice));
        recalculateTotalAmount();
    }
    
    private void recalculateTotalAmount() {
        this.totalAmount = items.stream()
            .map(OrderItem::subtotal)
            .reduce(Money.ZERO, Money::add);
    }
}
```

#### 4.4 领域服务（Domain Service）

当一个业务行为不属于任何单一实体时，用领域服务表达。

```java
// 转账：涉及两个账户，不属于任何一个账户
public class TransferDomainService {
    
    public void transfer(Account from, Account to, Money amount) {
        if (!from.canDebit(amount)) throw new InsufficientBalanceException();
        from.debit(amount);
        to.credit(amount);
        // 发布领域事件
        DomainEventPublisher.publish(new MoneyTransferredEvent(from.getId(), to.getId(), amount));
    }
}
```

#### 4.5 仓储（Repository）

抽象持久化，让领域层不依赖基础设施层。接口定义在领域层，实现在基础设施层。

```java
// 领域层：定义接口（只依赖领域对象）
public interface OrderRepository {
    Optional<Order> findById(OrderId id);
    List<Order> findByCustomerId(CustomerId customerId);
    void save(Order order);
    void remove(Order order);
}

// 基础设施层：具体实现（依赖 ORM）
@Repository
public class OrderRepositoryImpl implements OrderRepository {
    private final OrderJpaRepository jpaRepository;
    private final OrderMapper mapper;
    
    @Override
    public Optional<Order> findById(OrderId id) {
        return jpaRepository.findById(id.getValue())
            .map(mapper::toDomain);
    }
    
    @Override
    public void save(Order order) {
        OrderPO po = mapper.toPO(order);
        jpaRepository.save(po);
    }
}
```

#### 4.6 领域事件（Domain Event）

表达领域中发生的重要事实，用于聚合间的解耦。

```java
// 领域事件：不可变，代表已发生的事实
@Value
public class OrderSubmittedEvent implements DomainEvent {
    private final OrderId orderId;
    private final CustomerId customerId;
    private final Money totalAmount;
    private final Instant occurredAt = Instant.now();
}

// 聚合根发布事件
public class Order {
    private List<DomainEvent> domainEvents = new ArrayList<>();
    
    public void submit() {
        this.status = OrderStatus.SUBMITTED;
        domainEvents.add(new OrderSubmittedEvent(id, customerId, totalAmount));
    }
    
    public List<DomainEvent> getDomainEvents() {
        return Collections.unmodifiableList(domainEvents);
    }
    
    public void clearDomainEvents() {
        domainEvents.clear();
    }
}
```

#### 4.7 工厂（Factory）

封装复杂对象的创建逻辑。

```java
public class OrderFactory {
    
    public Order createFromCart(Cart cart, ShippingAddress address) {
        OrderId orderId = OrderId.generate();
        List<OrderItem> items = cart.getItems().stream()
            .map(cartItem -> new OrderItem(
                cartItem.getProductId(),
                cartItem.getQuantity(),
                cartItem.getUnitPrice()
            ))
            .collect(Collectors.toList());
        
        return new Order(orderId, cart.getCustomerId(), items, address);
    }
}
```

---

## 三、DDD 分层架构

```
┌─────────────────────────────────────┐
│           用户接口层 (UI Layer)       │  Controller、DTO、Assembler
│     REST API / GraphQL / gRPC       │
├─────────────────────────────────────┤
│         应用层 (Application Layer)   │  ApplicationService、Command、Query
│    协调领域对象，不含业务逻辑          │  事务控制、权限校验、事件监听
├─────────────────────────────────────┤
│          领域层 (Domain Layer)        │  Entity、ValueObject、Aggregate
│      核心业务规则，纯粹的业务逻辑       │  DomainService、Repository接口、DomainEvent
├─────────────────────────────────────┤
│       基础设施层 (Infrastructure)     │  Repository实现、ORM映射、消息队列
│    技术实现，对外部系统的适配           │  缓存、文件存储、第三方服务
└─────────────────────────────────────┘
         依赖方向：外层依赖内层，领域层不依赖任何层
```

---

## 四、Java 项目结构最佳实践

```
com.example.shop
├── interfaces/                          # 用户接口层
│   ├── rest/
│   │   ├── OrderController.java
│   │   └── dto/
│   │       ├── CreateOrderRequest.java
│   │       └── OrderResponse.java
│   └── assembler/
│       └── OrderAssembler.java          # DTO <-> 领域对象转换
│
├── application/                         # 应用层
│   ├── order/
│   │   ├── OrderApplicationService.java
│   │   ├── command/
│   │   │   ├── CreateOrderCommand.java
│   │   │   └── SubmitOrderCommand.java
│   │   └── query/
│   │       └── OrderQueryService.java
│   └── event/
│       └── PaymentCompletedEventHandler.java
│
├── domain/                              # 领域层（核心）
│   ├── order/
│   │   ├── Order.java                   # 聚合根
│   │   ├── OrderItem.java               # 实体
│   │   ├── OrderId.java                 # 值对象（ID）
│   │   ├── OrderStatus.java
│   │   ├── OrderRepository.java         # 仓储接口
│   │   └── event/
│   │       └── OrderSubmittedEvent.java # 领域事件
│   ├── customer/
│   │   ├── Customer.java
│   │   └── CustomerId.java
│   └── shared/
│       ├── Money.java                   # 共享值对象
│       └── DomainEvent.java
│
└── infrastructure/                      # 基础设施层
    ├── persistence/
    │   ├── OrderRepositoryImpl.java     # 仓储实现
    │   ├── po/
    │   │   └── OrderPO.java             # 持久化对象
    │   └── mapper/
    │       └── OrderMapper.java         # 对象转换
    └── messaging/
        └── RabbitMQEventPublisher.java
```

---

## 五、完整示例：订单提交流程

### 5.1 领域层

```java
// OrderId.java - 强类型 ID 值对象
@Value
public class OrderId {
    private final String value;
    
    public static OrderId generate() {
        return new OrderId(UUID.randomUUID().toString());
    }
    
    public static OrderId of(String value) {
        return new OrderId(value);
    }
}

// Order.java - 聚合根
@Getter
public class Order {
    private OrderId id;
    private CustomerId customerId;
    private List<OrderItem> items;
    private Money totalAmount;
    private OrderStatus status;
    private Address shippingAddress;
    private final List<DomainEvent> domainEvents = new ArrayList<>();
    
    // 通过工厂方法或构造器创建，保证初始状态合法
    public Order(OrderId id, CustomerId customerId, Address shippingAddress) {
        this.id = Objects.requireNonNull(id);
        this.customerId = Objects.requireNonNull(customerId);
        this.shippingAddress = Objects.requireNonNull(shippingAddress);
        this.items = new ArrayList<>();
        this.totalAmount = Money.ZERO;
        this.status = OrderStatus.DRAFT;
    }
    
    public void addItem(ProductId productId, int quantity, Money unitPrice) {
        ensureStatus(OrderStatus.DRAFT);
        if (quantity <= 0) throw new DomainException("数量必须大于0");
        items.add(new OrderItem(productId, quantity, unitPrice));
        recalculate();
    }
    
    public void submit() {
        ensureStatus(OrderStatus.DRAFT);
        if (items.isEmpty()) throw new DomainException("订单不能为空");
        this.status = OrderStatus.SUBMITTED;
        addDomainEvent(new OrderSubmittedEvent(id, customerId, totalAmount));
    }
    
    public void cancel(String reason) {
        if (status == OrderStatus.DELIVERED) throw new DomainException("已送达的订单不能取消");
        this.status = OrderStatus.CANCELLED;
        addDomainEvent(new OrderCancelledEvent(id, reason));
    }
    
    private void ensureStatus(OrderStatus expected) {
        if (this.status != expected)
            throw new DomainException(String.format("订单状态必须为 %s，当前为 %s", expected, status));
    }
    
    private void recalculate() {
        this.totalAmount = items.stream()
            .map(OrderItem::getSubtotal)
            .reduce(Money.ZERO, Money::add);
    }
    
    private void addDomainEvent(DomainEvent event) {
        domainEvents.add(event);
    }
    
    public List<DomainEvent> pullDomainEvents() {
        List<DomainEvent> events = new ArrayList<>(domainEvents);
        domainEvents.clear();
        return events;
    }
}
```

### 5.2 应用层

```java
// SubmitOrderCommand.java
@Value
public class SubmitOrderCommand {
    private final String orderId;
    private final String operatorId;
}

// OrderApplicationService.java
@Service
@Transactional
@RequiredArgsConstructor
public class OrderApplicationService {
    
    private final OrderRepository orderRepository;
    private final DomainEventPublisher eventPublisher;
    
    public void submitOrder(SubmitOrderCommand command) {
        // 1. 加载聚合根
        OrderId orderId = OrderId.of(command.getOrderId());
        Order order = orderRepository.findById(orderId)
            .orElseThrow(() -> new OrderNotFoundException(orderId));
        
        // 2. 执行领域操作（业务逻辑在领域层）
        order.submit();
        
        // 3. 持久化
        orderRepository.save(order);
        
        // 4. 发布领域事件
        eventPublisher.publishAll(order.pullDomainEvents());
    }
}
```

### 5.3 用户接口层

```java
// CreateOrderRequest.java - 请求 DTO（与领域对象解耦）
@Data
public class CreateOrderRequest {
    private String customerId;
    private List<OrderItemDTO> items;
    private AddressDTO shippingAddress;
}

// OrderController.java
@RestController
@RequestMapping("/api/orders")
@RequiredArgsConstructor
public class OrderController {
    
    private final OrderApplicationService orderAppService;
    private final OrderAssembler assembler;
    
    @PostMapping("/{orderId}/submit")
    public ResponseEntity<Void> submitOrder(@PathVariable String orderId) {
        orderAppService.submitOrder(new SubmitOrderCommand(orderId, getCurrentUserId()));
        return ResponseEntity.ok().build();
    }
}
```

---

## 六、CQRS 模式（命令查询职责分离）

DDD 常与 CQRS 结合使用，将写操作（Command）和读操作（Query）分离。

```
写模型（Command Side）                 读模型（Query Side）
┌─────────────────────┐               ┌─────────────────────┐
│  Command            │               │  Query              │
│  ApplicationService │               │  Service            │
│  Domain Model       │    同步/异步    │  Read Model(DTO)    │
│  Repository         │ ──────────►   │  直接查询数据库       │
│  (复杂业务规则)       │               │  (可有自己的读库)     │
└─────────────────────┘               └─────────────────────┘
```

```java
// 查询服务：绕过领域模型，直接用 SQL/JPQL 查询，返回 DTO
@Service
@RequiredArgsConstructor
public class OrderQueryService {
    
    private final EntityManager em;
    
    public OrderDetailDTO findOrderDetail(String orderId) {
        // 直接返回 DTO，不经过领域对象转换，性能更好
        return em.createQuery(
            "SELECT new com.example.dto.OrderDetailDTO(o.id.value, o.status, o.totalAmount.amount) " +
            "FROM Order o WHERE o.id.value = :orderId", OrderDetailDTO.class)
            .setParameter("orderId", orderId)
            .getSingleResult();
    }
}
```

---

## 七、防腐层（Anti-Corruption Layer）示例

集成外部系统时，防止外部模型污染内部领域。

```java
// 外部支付系统返回的模型（丑陋的外部契约）
public class AlipayPaymentResult {
    public String out_trade_no;
    public String trade_status;
    public String total_amount;
    public String buyer_id;
}

// 防腐层：将外部模型转为内部领域概念
@Component
public class AlipayAntiCorruptionLayer {
    
    public PaymentCompletedEvent translate(AlipayPaymentResult result) {
        return new PaymentCompletedEvent(
            OrderId.of(result.out_trade_no),
            new Money(new BigDecimal(result.total_amount), Currency.CNY),
            "ALIPAY".equals(result.trade_status.startsWith("TRADE") ? "SUCCESS" : "FAIL")
                .equals("SUCCESS") ? PaymentStatus.SUCCESS : PaymentStatus.FAILED
        );
    }
}
```

---

## 八、DDD 实践常见误区

| 误区 | 正确做法 |
|------|---------|
| **贫血模型**：Entity 只有 getter/setter，业务逻辑全在 Service | 把业务行为放到 Entity/ValueObject 中，让对象真正"活起来" |
| **大聚合**：把所有相关对象都塞进一个聚合 | 聚合尽量小，只包含必须强一致的对象 |
| **Repository 当 DAO 用**：暴露大量 findByXxx 方法 | Repository 面向聚合根，查询逻辑用 Specification 或 QueryService |
| **领域层依赖框架**：Entity 上堆满 @Entity, @Table 注解 | 使用映射层隔离 JPA 注解，或用 Spring Data 的接口方式 |
| **忽略通用语言**：方法命名与业务术语脱节 | 代码命名与业务专家达成一致，直接反映业务语言 |
| **跨聚合直接调用**：聚合 A 直接修改聚合 B 的状态 | 通过领域事件实现聚合间的最终一致性 |

---

## 九、DDD 适用场景

**适合 DDD：**
- 业务逻辑复杂、规则多变的核心域（如电商、金融、保险）
- 需要长期演进的系统
- 多团队协作，需要明确边界

**不适合 DDD：**
- CRUD 为主的简单业务系统
- 数据分析、报表系统
- 快速原型、短生命周期项目

---

## 十、推荐学习资源

- 📖 **《领域驱动设计》** - Eric Evans（蓝皮书，DDD 奠基之作）
- 📖 **《实现领域驱动设计》** - Vaughn Vernon（红皮书，更多实践）
- 📖 **《领域驱动设计精粹》** - Vaughn Vernon（入门首选）
- 🔗 [DDD Community](https://dddcommunity.org/)

---

## 十一、贫血模型 vs 充血模型

这是 DDD 中最核心的争议，也是大多数项目的分水岭。

### 11.1 贫血模型（Anemic Domain Model）

Martin Fowler 称其为**反模式**。对象只有数据（getter/setter），没有行为，业务逻辑全部堆在 Service 层。

```java
// ❌ 贫血模型：Order 只是数据容器
@Data
@Entity
public class Order {
    private Long id;
    private String status;
    private BigDecimal totalAmount;
    private List<OrderItem> items;
    // 只有 getter/setter，零业务逻辑
}

// ❌ 所有业务逻辑堆在 Service 里，变成"过程式"代码
@Service
public class OrderService {

    public void submitOrder(Long orderId) {
        Order order = orderRepository.findById(orderId);

        // 状态校验散落在 Service 中，无法复用
        if (!"DRAFT".equals(order.getStatus())) {
            throw new RuntimeException("状态错误");
        }
        if (order.getItems() == null || order.getItems().isEmpty()) {
            throw new RuntimeException("订单为空");
        }

        // 金额计算散落在 Service 中
        BigDecimal total = order.getItems().stream()
            .map(item -> item.getUnitPrice().multiply(BigDecimal.valueOf(item.getQuantity())))
            .reduce(BigDecimal.ZERO, BigDecimal::add);
        order.setTotalAmount(total);

        // 状态变更散落在 Service 中
        order.setStatus("SUBMITTED");
        orderRepository.save(order);
    }

    public void cancelOrder(Long orderId, String reason) {
        Order order = orderRepository.findById(orderId);
        // 同样的状态判断逻辑在这里又写一遍
        if ("DELIVERED".equals(order.getStatus())) {
            throw new RuntimeException("已送达不能取消");
        }
        order.setStatus("CANCELLED");
        orderRepository.save(order);
    }
}
```

**贫血模型的危害：**
- 业务逻辑分散，无处聚合，极难维护
- 同一规则（如状态校验）在多个 Service 重复出现
- 对象本身毫无意义，只是数据库表的映射
- 单元测试困难，必须 Mock 大量依赖
- 随着业务增长，Service 变成"上帝类"，几千行无法拆分

---

### 11.2 充血模型（Rich Domain Model）

对象同时拥有数据和行为，业务规则封装在领域对象内部，Service 只做编排。

```java
// ✅ 充血模型：Order 拥有完整的业务行为
public class Order {
    private OrderId id;
    private OrderStatus status;
    private List<OrderItem> items = new ArrayList<>();
    private Money totalAmount;

    // 业务行为：添加明细（含不变性保护）
    public void addItem(ProductId productId, int quantity, Money unitPrice) {
        if (status != OrderStatus.DRAFT)
            throw new DomainException("只有草稿状态才能添加明细");
        if (quantity <= 0)
            throw new DomainException("数量必须大于0");
        if (items.size() >= 50)
            throw new DomainException("明细不能超过50条");

        items.add(new OrderItem(productId, quantity, unitPrice));
        recalculate();  // 自动重算金额
    }

    // 业务行为：提交订单
    public void submit() {
        if (status != OrderStatus.DRAFT)
            throw new DomainException("只有草稿状态才能提交");
        if (items.isEmpty())
            throw new DomainException("订单不能为空");
        this.status = OrderStatus.SUBMITTED;
        this.submittedAt = Instant.now();
        registerEvent(new OrderSubmittedEvent(id, customerId, totalAmount));
    }

    // 业务行为：取消订单（规则内聚在此，不会遗漏）
    public void cancel(String reason) {
        if (status == OrderStatus.DELIVERED)
            throw new DomainException("已送达的订单不能取消");
        if (status == OrderStatus.CANCELLED)
            throw new DomainException("订单已经取消");
        this.status = OrderStatus.CANCELLED;
        registerEvent(new OrderCancelledEvent(id, reason));
    }

    // 业务查询：可以发货吗？
    public boolean canShip() {
        return status == OrderStatus.PAID && items.stream().allMatch(OrderItem::isInStock);
    }

    private void recalculate() {
        this.totalAmount = items.stream()
            .map(OrderItem::getSubtotal)
            .reduce(Money.ZERO, Money::add);
    }
}

// ✅ ApplicationService 变得极其简洁，只做编排
@Service
public class OrderApplicationService {

    public void submitOrder(SubmitOrderCommand cmd) {
        Order order = orderRepository.findById(OrderId.of(cmd.getOrderId()))
            .orElseThrow(OrderNotFoundException::new);
        order.submit();   // 一行：业务规则全在领域对象里
        orderRepository.save(order);
        eventPublisher.publishAll(order.pullDomainEvents());
    }
}
```

---

### 11.3 两种模型的对比

```
贫血模型                              充血模型
┌──────────────┐                    ┌──────────────────────────┐
│   Service    │  业务规则全在这里    │   Order (聚合根)           │
│  (上帝类)     │ ─────────────────► │   + submit()             │
│              │                    │   + cancel()             │
│   Order      │  只是数据容器        │   + addItem()            │
│  (贫血对象)   │                    │   + canShip()            │
└──────────────┘                    └──────────────────────────┘
   规则分散，难复用                      规则内聚，易测试易复用
```

| 维度 | 贫血模型 | 充血模型 |
|------|---------|---------|
| 业务逻辑位置 | Service 层 | 领域对象内部 |
| 代码复用 | 差，规则分散易重复 | 好，规则内聚在对象里 |
| 可读性 | Service 越来越臃肿 | 对象即文档，一目了然 |
| 单元测试 | 难，Service 依赖多 | 易，直接 `new Order()` 测试 |
| 对象封装性 | 破坏封装（setter 公开） | 强封装，状态由对象自身控制 |
| 适用场景 | 简单 CRUD 系统 | 复杂业务系统 |

---

## 十二、子域分类（Domain Classification）

不是所有业务都值得投入相同精力，DDD 将业务域分为三类：

```
┌─────────────────────────────────────────────────────┐
│                     业务全景                          │
│                                                     │
│   ┌─────────────────┐                               │
│   │   核心域          │  ← 投入最多，自研，DDD 重点    │
│   │  Core Domain    │                               │
│   │  (竞争优势所在)   │                               │
│   └─────────────────┘                               │
│                                                     │
│   ┌─────────────────┐  ┌─────────────────┐          │
│   │   支撑域          │  │   通用域          │          │
│   │ Supporting      │  │  Generic        │          │
│   │ Domain          │  │  Domain         │          │
│   │ (定制开发)        │  │  (购买/开源)      │          │
│   └─────────────────┘  └─────────────────┘          │
└─────────────────────────────────────────────────────┘
```

| 类型 | 说明 | 策略 |
|------|------|------|
| **核心域（Core Domain）** | 公司核心竞争力，业务独特性所在（如电商的推荐算法、金融的风控模型） | 最优秀的工程师 + DDD 精细建模，自研 |
| **支撑域（Supporting Domain）** | 支持核心域运转，非竞争优势（如订单管理、仓储） | 内部开发，够用即可，或外包 |
| **通用域（Generic Domain）** | 行业通用能力，无差异化（如认证、支付、短信） | 购买 SaaS / 使用开源方案 |

---

## 十三、规格模式（Specification Pattern）

用于将业务规则封装为可组合的对象，解决复杂查询和业务验证的问题。

```java
// 规格接口
public interface Specification<T> {
    boolean isSatisfiedBy(T candidate);

    default Specification<T> and(Specification<T> other) {
        return candidate -> this.isSatisfiedBy(candidate) && other.isSatisfiedBy(candidate);
    }

    default Specification<T> or(Specification<T> other) {
        return candidate -> this.isSatisfiedBy(candidate) || other.isSatisfiedBy(candidate);
    }

    default Specification<T> not() {
        return candidate -> !this.isSatisfiedBy(candidate);
    }
}

// 具体规格：VIP 客户
public class VipCustomerSpec implements Specification<Customer> {
    @Override
    public boolean isSatisfiedBy(Customer customer) {
        return customer.getTotalSpent().compareTo(new Money(10000, CNY)) >= 0;
    }
}

// 具体规格：活跃客户（近30天有购买）
public class ActiveCustomerSpec implements Specification<Customer> {
    @Override
    public boolean isSatisfiedBy(Customer customer) {
        return customer.getLastOrderDate().isAfter(Instant.now().minus(30, DAYS));
    }
}

// 组合使用：VIP 且活跃的客户才能参加活动
Specification<Customer> eligibleForPromotion =
    new VipCustomerSpec().and(new ActiveCustomerSpec());

List<Customer> eligible = customers.stream()
    .filter(eligibleForPromotion::isSatisfiedBy)
    .collect(Collectors.toList());
```

与 JPA 结合（Spring Data Specification）：

```java
// 将规格转为 JPA 查询条件
public class OrderSpecifications {

    public static Specification<OrderPO> hasStatus(OrderStatus status) {
        return (root, query, cb) -> cb.equal(root.get("status"), status.name());
    }

    public static Specification<OrderPO> createdAfter(Instant time) {
        return (root, query, cb) -> cb.greaterThan(root.get("createdAt"), time);
    }

    public static Specification<OrderPO> belongsTo(CustomerId customerId) {
        return (root, query, cb) -> cb.equal(root.get("customerId"), customerId.getValue());
    }
}

// 使用：查询某客户近7天的已提交订单
Specification<OrderPO> spec = where(belongsTo(customerId))
    .and(hasStatus(SUBMITTED))
    .and(createdAfter(Instant.now().minus(7, DAYS)));

List<OrderPO> orders = orderJpaRepository.findAll(spec);
```

---

## 十四、Saga 模式（跨聚合的最终一致性）

聚合间不能用数据库事务保证一致性，Saga 是标准解法。

### 14.1 编排式 Saga（Choreography）

各服务自己监听事件、自己决定下一步，无中心协调者。

```
订单服务              库存服务              支付服务
   │                    │                    │
   │ OrderSubmitted ──► │                    │
   │                    │ StockReserved ──► │
   │                    │                    │ PaymentCompleted
   │ ◄─────────────────────────────────────  │
   │ (监听事件，更新状态)                       │
```

```java
// 库存服务：监听订单提交事件
@EventListener
public void onOrderSubmitted(OrderSubmittedEvent event) {
    try {
        inventory.reserve(event.getOrderId(), event.getItems());
        eventPublisher.publish(new StockReservedEvent(event.getOrderId()));
    } catch (InsufficientStockException e) {
        eventPublisher.publish(new StockReservationFailedEvent(event.getOrderId()));
    }
}

// 订单服务：监听库存失败事件，执行补偿
@EventListener
public void onStockReservationFailed(StockReservationFailedEvent event) {
    Order order = orderRepository.findById(event.getOrderId()).orElseThrow();
    order.failDueToStock();  // 业务补偿
    orderRepository.save(order);
}
```

### 14.2 协调式 Saga（Orchestration）

中心协调者（Saga Orchestrator）统一驱动流程，适合复杂流程。

```java
@Component
public class OrderSagaOrchestrator {

    // Saga 状态机：驱动整个下单流程
    public void handle(OrderSubmittedEvent event) {
        SagaState saga = sagaRepository.create(event.getOrderId());

        try {
            // Step 1: 锁定库存
            saga.setStep("RESERVE_STOCK");
            inventoryService.reserve(event.getOrderId(), event.getItems());

            // Step 2: 扣减积分
            saga.setStep("DEDUCT_POINTS");
            pointsService.deduct(event.getCustomerId(), event.getPoints());

            // Step 3: 发起支付
            saga.setStep("INITIATE_PAYMENT");
            paymentService.initiate(event.getOrderId(), event.getTotalAmount());

            saga.complete();
        } catch (Exception e) {
            // 回滚已完成的步骤（补偿事务）
            compensate(saga, event);
        }
    }

    private void compensate(SagaState saga, OrderSubmittedEvent event) {
        if (saga.reachedStep("DEDUCT_POINTS"))
            pointsService.refund(event.getCustomerId(), event.getPoints());
        if (saga.reachedStep("RESERVE_STOCK"))
            inventoryService.release(event.getOrderId());
        saga.fail();
    }
}
```

---

## 十五、事件溯源（Event Sourcing）

不存储当前状态，而是存储所有导致状态变化的**事件序列**，通过重放事件得到当前状态。

```
传统方式：存储最终状态
┌─────────────────────────────┐
│ order_id │ status │ amount  │
│ 001      │ PAID   │ 299.00  │  ← 只有当前快照，历史丢失
└─────────────────────────────┘

事件溯源：存储事件流
┌──────────────────────────────────────────────────┐
│ order_id │ event_type          │ payload          │
│ 001      │ OrderCreated        │ {customerId:...} │
│ 001      │ ItemAdded           │ {productId:...}  │
│ 001      │ OrderSubmitted      │ {amount: 299}    │
│ 001      │ PaymentCompleted    │ {txId:...}       │  ← 完整历史
└──────────────────────────────────────────────────┘
```

```java
// 聚合根通过重放事件重建状态
public class Order {
    private OrderId id;
    private OrderStatus status;
    private List<OrderItem> items = new ArrayList<>();
    private List<DomainEvent> uncommittedEvents = new ArrayList<>();

    // 从事件流重建（EventSourcing 核心）
    public static Order reconstitute(List<DomainEvent> eventStream) {
        Order order = new Order();
        eventStream.forEach(order::apply);
        return order;
    }

    // 业务操作：产生事件
    public void submit() {
        if (status != OrderStatus.DRAFT) throw new DomainException("状态错误");
        applyAndRecord(new OrderSubmittedEvent(id, Instant.now()));
    }

    private void applyAndRecord(DomainEvent event) {
        apply(event);                    // 变更状态
        uncommittedEvents.add(event);    // 记录待持久化事件
    }

    // 状态变更只通过 apply 触发，保证一致性
    private void apply(DomainEvent event) {
        if (event instanceof OrderCreatedEvent e) {
            this.id = e.getOrderId();
            this.status = OrderStatus.DRAFT;
        } else if (event instanceof ItemAddedEvent e) {
            this.items.add(new OrderItem(e.getProductId(), e.getQuantity(), e.getUnitPrice()));
        } else if (event instanceof OrderSubmittedEvent e) {
            this.status = OrderStatus.SUBMITTED;
        } else if (event instanceof PaymentCompletedEvent e) {
            this.status = OrderStatus.PAID;
        }
    }
}
```

**事件溯源的优缺点：**

| 优点 | 缺点 |
|------|------|
| 完整审计日志，天然可追溯 | 实现复杂度高 |
| 可时间旅行（重放到任意时间点） | 查询需要额外的读模型（配合 CQRS） |
| 易于调试，可重现任何历史状态 | 事件 Schema 演化困难 |
| 天然的领域事件产生机制 | 聚合加载需重放所有事件（需快照优化） |

---

## 十六、Repository 与 DAO 的本质区别

很多人把 Repository 当 DAO 用，这是常见误区。

```
DAO（Data Access Object）              Repository（仓储）
┌──────────────────────────┐          ┌──────────────────────────┐
│ 面向数据库表               │          │ 面向领域聚合根              │
│ findByUserId()           │          │ findById(UserId)          │
│ findByStatusAndDate()    │          │ save(Order)              │
│ updateStatus()           │          │ remove(Order)            │
│ batchInsert()            │          │ findBySpecification()    │
│                          │          │                          │
│ 返回：数据库行/Map/DTO      │          │ 返回：完整的聚合根对象        │
│ 不关心业务含义              │          │ 关心业务完整性              │
└──────────────────────────┘          └──────────────────────────┘
   基础设施概念                            领域层概念（接口在领域层）
```

```java
// ❌ Repository 被当成 DAO 滥用
public interface OrderRepository {
    List<Order> findByStatusAndCreatedAtBetween(String status, Date start, Date end);
    int updateStatusById(Long id, String status);     // 绕过聚合根直接改状态！
    void batchInsert(List<Order> orders);             // 批量操作跳过领域规则
    List<Map<String, Object>> findOrderSummary();     // 返回非领域对象
}

// ✅ Repository 正确用法：面向聚合根，隐藏持久化细节
public interface OrderRepository {
    Optional<Order> findById(OrderId id);
    List<Order> findByCustomerId(CustomerId customerId);
    List<Order> findAll(Specification<Order> spec);   // 规格模式
    void save(Order order);     // 新增和更新都是 save
    void remove(Order order);
}
// 复杂查询 → OrderQueryService（CQRS 读模型），不放在 Repository
```

---

## 十七、应用服务 vs 领域服务 vs 基础设施服务

三种"服务"概念容易混淆，核心区别如下：

```
┌──────────────────────────────────────────────────────────────┐
│                      应用服务 (ApplicationService)             │
│  职责：编排、事务、权限、事件发布，不含业务逻辑                     │
│  依赖：Repository、DomainService、外部服务                      │
│  示例：OrderApplicationService.submitOrder()                  │
├──────────────────────────────────────────────────────────────┤
│                      领域服务 (DomainService)                  │
│  职责：跨聚合的业务逻辑，无法归属于任何单一实体                     │
│  依赖：只依赖领域对象，不依赖 Repository 和框架                   │
│  示例：TransferDomainService.transfer(from, to, amount)       │
├──────────────────────────────────────────────────────────────┤
│                   基础设施服务 (InfrastructureService)          │
│  职责：技术能力封装（发邮件、发短信、调用第三方 API）               │
│  依赖：外部系统、框架                                           │
│  示例：EmailService、SmsService、AlipayGateway                │
└──────────────────────────────────────────────────────────────┘
```

```java
// 领域服务：纯业务逻辑，无框架依赖，可以直接单元测试
public class PricingDomainService {

    // 计算最终价格：涉及多个领域概念，不属于任何一个
    public Money calculateFinalPrice(Order order, Customer customer, List<Coupon> coupons) {
        Money basePrice = order.getTotalAmount();
        Money discount = calculateDiscount(customer, basePrice);
        Money couponDeduction = applyCoupons(coupons, basePrice.subtract(discount));
        return basePrice.subtract(discount).subtract(couponDeduction);
    }
}

// 应用服务：编排领域服务 + 基础设施服务
@Service
@Transactional
public class OrderApplicationService {

    private final OrderRepository orderRepository;
    private final PricingDomainService pricingService;   // 领域服务
    private final PaymentGateway paymentGateway;          // 基础设施服务
    private final DomainEventPublisher eventPublisher;

    public PaymentResult checkout(CheckoutCommand cmd) {
        Order order = orderRepository.findById(cmd.getOrderId()).orElseThrow();
        Customer customer = customerRepository.findById(order.getCustomerId()).orElseThrow();
        List<Coupon> coupons = couponRepository.findByIds(cmd.getCouponIds());

        // 调用领域服务计算价格
        Money finalPrice = pricingService.calculateFinalPrice(order, customer, coupons);

        // 调用基础设施服务发起支付
        PaymentResult result = paymentGateway.pay(order.getId(), finalPrice, cmd.getPayMethod());

        // 更新领域状态
        if (result.isSuccess()) order.confirmPayment(finalPrice);
        orderRepository.save(order);
        eventPublisher.publishAll(order.pullDomainEvents());

        return result;
    }
}
```

---

## 十八、对象类型速查表

| 对象类型 | 有 ID？ | 可变？ | 相等判断 | 生命周期 | 典型示例 |
|---------|--------|-------|---------|---------|---------|
| **实体 Entity** | ✅ 是 | ✅ 可变 | 靠 ID | 独立 | Order, Customer, Product |
| **值对象 ValueObject** | ❌ 否 | ❌ 不可变 | 靠属性值 | 依附实体 | Money, Address, Email |
| **聚合根 Aggregate Root** | ✅ 是 | ✅ 可变 | 靠 ID | 独立（事务边界） | Order（含OrderItem） |
| **领域事件 Domain Event** | 可选 | ❌ 不可变 | 靠事件ID | 短暂 | OrderSubmittedEvent |
| **领域服务 Domain Service** | ❌ 无状态 | — | — | 无状态 | TransferDomainService |
| **应用服务 App Service** | ❌ 无状态 | — | — | 无状态 | OrderApplicationService |
| **工厂 Factory** | ❌ 无状态 | — | — | 无状态 | OrderFactory |
| **仓储 Repository** | ❌ 无状态 | — | — | 无状态 | OrderRepository |
