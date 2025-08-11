
## Ghidra获取静态调用信息
Ghidra 提供了功能非常强大的 Jython API，可以帮助您获取详细的函数调用信息。您可以编写 Python 脚本来遍历一个 SO（或任何二进制文件）中的所有函数，并找出每个函数调用的其他函数，最终以您期望的 `Dict[int, Set[int]]` 格式返回结果。

其核心是使用 `FunctionManager` 来获取所有函数，然后对每个 `Function` 对象使用 `getCalledFunctions()` 方法来获取其调用的函数集合。

### Python 脚本示例

以下是一个可以在 Ghidra 的脚本管理器 (Script Manager) 中运行的 Python 脚本，它将实现您所要求的功能：

```python
# 获取当前程序中所有函数的调用图信息
# @author Ghidra
# @category Analysis
# @keybinding
# @menupath
# @toolbar

# 导入必要的Ghidra API类
from ghidra.util.task import ConsoleTaskMonitor

def get_function_call_graph():
    """
    分析当前程序，生成一个函数调用图。

    返回:
        dict: 一个字典，键是调用者函数的起始偏移量(int)，
              值是一个包含所有被调用函数起始偏移量的集合(set)。
    """
    call_graph = {}
    
    # 获取函数管理器，用于访问程序中的所有函数
    function_manager = currentProgram.getFunctionManager()
    
    # 创建一个任务监视器，某些API调用需要此参数
    monitor = ConsoleTaskMonitor()
    
    # getFunctions(True)返回一个可以遍历所有函数（按地址升序）的迭代器
    all_functions = function_manager.getFunctions(True)
    
    print("正在分析 {} 个函数...".format(function_manager.getFunctionCount()))
    
    for caller_function in all_functions:
        # 获取调用者函数的入口点地址，并转换为偏移量
        # getEntryPoint() 返回 Address 对象, getOffset() 返回 long (在Jython中是int)
        caller_offset = caller_function.getEntryPoint().getOffset()
        
        # 初始化一个集合来存储被调用函数的偏移量
        callee_offsets = set()
        
        # getCalledFunctions() 返回一个被此函数调用的 Function 对象的集合
        # 这包括了直接调用和已解析的间接调用
        called_functions = caller_function.getCalledFunctions(monitor)
        
        for callee_function in called_functions:
            # 获取被调用函数的入口点偏移量
            callee_offset = callee_function.getEntryPoint().getOffset()
            callee_offsets.add(callee_offset)
            
        # 将结果存入调用图字典中
        # 只有当函数有调用其他函数时才添加，以保持字典整洁
        if callee_offsets:
            call_graph[caller_offset] = callee_offsets
            
    return call_graph

if __name__ == '__main__':
    # 执行函数并获取调用图
    function_calls = get_function_call_graph()
    
    print("\n--- 函数调用图 (调用者偏移量 -> {被调用者偏移量,...}) ---\n")
    
    # 为了方便查看，对结果进行排序和格式化打印
    for caller_offset in sorted(function_calls.keys()):
        # 将偏移量集合转换为排序后的列表，并格式化为十六进制字符串
        callees_str = ", ".join(hex(o) for o in sorted(list(function_calls[caller_offset])))
        print("{} -> {{{}}}".format(hex(caller_offset), callees_str))
        
    print("\n分析完成！共找到 {} 个发起调用的函数。".format(len(function_calls)))

```

### 如何使用该脚本

1.  **打开 Ghidra**：加载并分析您要研究的 `.so` 文件。
2.  **打开脚本管理器**：在 Ghidra 顶部菜单栏选择 `Window` -> `Script Manager`。
3.  **新建脚本**：在脚本管理器窗口中，点击工具栏上的 "Create New Script" 图标，选择 `Python`作为语言。
4.  **粘贴代码**：将上面的代码完整地粘贴到新打开的脚本编辑器中。
5.  **运行脚本**：保存脚本，然后在脚本管理器中选中该脚本，点击工具栏的 "Run Script" (绿色播放按钮) 图标。
6.  **查看结果**：脚本的输出将显示在 Ghidra 的控制台窗口中 (Console Window)，您可以通过 `Window` -> `Console` 打开。

### 工作原理解释

*   **`currentProgram`**: 这是一个全局变量，代表当前在 Ghidra 中加载和分析的程序。
*   **`getFunctionManager()`**: 通过 `currentProgram` 对象可以获取到 `FunctionManager` 的实例，这是管理程序中所有函数的入口。
*   **`getFunctions(True)`**: 这个方法返回一个迭代器，可以遍历程序中定义的所有函数。 参数 `True` 表示按地址顺序正向迭代。
*   **`getEntryPoint()`**: 每个 `Function` 对象都有一个 `getEntryPoint()` 方法，返回该函数的起始地址（一个 `Address` 对象）。
*   **`getOffset()`**: `Address` 对象拥有 `getOffset()` 方法，它返回一个长整型（在 Python 中是 `int`），代表了该地址相对于基地址的偏移量，这正是您所需要的键和值。
*   **`getCalledFunctions(monitor)`**: 这是最关键的方法。 对于一个给定的 `Function` 对象，它会返回一个 `Set`，其中包含了所有被该函数调用的其他 `Function` 对象。Ghidra 的反编译器在分析过程中，会解析直接调用（如 `BL`）和部分间接调用（如通过 PLT/GOT 对外部函数的调用），这些已解析的目标都会被这个方法返回。

### 关于间接调用的注意事项

*   **已解析的间接调用**：正如前面提到的，对于通过 PLT/GOT 调用的外部函数，Ghidra 在分析后能够确定其目标。因此，`getCalledFunctions()` 的结果会包含这些外部函数。
*   **未解析的间接调用**：如果一个间接调用（例如 `BLR X16`）的目标地址是在运行时通过复杂的计算动态确定的，Ghidra 可能无法在静态分析时解析出其具体目标。在这种情况下，这次调用将**不会**出现在 `getCalledFunctions()` 的返回结果中。脚本的输出完全依赖于 Ghidra 静态分析的能力。


## Frida获取间接调用信息
1.  **确定目标SO文件**：我们的脚本需要知道要以哪个共享库（`.so`文件）为基准来计算偏移量。我们将通过命令行参数将这个模块名传递给我们的Python控制器，再由控制器传递给Frida Agent。
2.  **获取模块基地址**：在Frida Agent中，我们需要找到目标SO文件的基地址（`module.base`）。
3.  **过滤调用点**：我们只对源于目标SO文件内部的间接调用感兴趣。因此，Stalker需要过滤掉所有不在该模块地址范围内的指令。
4.  **计算偏移量**：
    *   对于**调用点（Call Site）**，其偏移量为 `call_site_address - module.base`。
    *   对于**调用目标（Call Target）**，我们需要先判断它是否也落在目标SO文件内。
        *   如果是，其表示为偏移量 `call_target_address - module.base`。
        *   如果不是（例如，调用了`libc.so`中的函数），我们将其表示为 `module_name!offset_in_that_module`，这样信息更完整，也更具可读性。
5.  **通信和数据聚合**：继续使用之前的Controller/Agent模型，但Agent发送的消息将包含计算好的偏移量和模块信息，Controller负责聚合这些结构化的数据。

---

### 第1步：Agent脚本 (`agent-offset.ts`)

这个脚本现在会接收一个目标模块名，并进行所有地址到偏移量的转换。

```typescript
// agent-offset.ts

// 这些变量将在init函数中被设置
let targetModule: Module | null = null;

/**
 * 将一个绝对地址解析为其所属模块和模块内偏移量
 * @param address 要解析的地址
 * @returns 一个包含模块名和偏移量的对象
 */
function resolveAddress(address: NativePointer): { module: string | null; offset: NativePointer } {
    const module = Process.findModuleByAddress(address);
    if (module) {
        return {
            module: module.name,
            offset: address.sub(module.base),
        };
    }
    // 如果地址不在任何已知模块中（例如JIT代码或堆内存）
    return {
        module: null,
        offset: address, // 在这种情况下，偏移量就是绝对地址
    };
}


/**
 * Stalker的核心逻辑，只插桩目标模块内的指令
 */
function stalkThread(threadId: number) {
    Stalker.follow(threadId, {
        transform: (iterator: Stalker.TransformIterator) => {
            let instruction: cs.Instruction | null;
            // 确保我们已经初始化了目标模块
            if (!targetModule) return;

            while ((instruction = iterator.next()) !== null) {
                const instrAddr = instruction.address;

                // 关键优化：只处理在目标模块地址范围内的指令
                if (instrAddr.compare(targetModule.base) >= 0 && instrAddr.compare(targetModule.base.add(targetModule.size)) < 0) {
                    iterator.keep();

                    const mnemonic = instruction.mnemonic;
                    if ((mnemonic === 'blr' || mnemonic === 'br') && instruction.operands[0]?.type === 'reg') {
                        iterator.putCallout((context: Arm64CpuContext) => {
                            const regName = instruction.opStr as keyof Arm64CpuContext;
                            const targetAddress = context[regName] as NativePointer;

                            if (targetAddress.isNull()) {
                                return;
                            }

                            // 解析调用点和目标地址
                            const siteInfo = resolveAddress(instrAddr);
                            const targetInfo = resolveAddress(targetAddress);

                            // 将结构化的信息发送给Python控制器
                            send({
                                type: 'indirect-call',
                                site: siteInfo,
                                target: targetInfo,
                            });
                        });
                    } else {
                        iterator.keep();
                    }
                } else {
                    // 对于不在目标模块内的代码，直接跳过，不做任何插桩
                    iterator.keep();
                }
            }
        },
    });
}

// 使用RPC从Python控制器接收初始化信息
rpc.exports = {
    init(moduleName: string) {
        console.log(`[Agent] Initializing for module: ${moduleName}`);
        targetModule = Process.findModuleByName(moduleName);
        if (!targetModule) {
            const errorMsg = `[Agent] Error: Module '${moduleName}' not found.`;
            console.error(errorMsg);
            // 也将错误发送回控制器
            send({ type: 'error', message: errorMsg });
            return;
        }

        console.log(`[Agent] Found module '${targetModule.name}' at ${targetModule.base} (size: ${targetModule.size})`);
        console.log(`[Agent] Attaching Stalker to all threads...`);

        Process.enumerateThreads().forEach(thread => stalkThread(thread.id));

        console.log(`[Agent] Ready.`);
    },
};
```

### 第2步：Controller脚本 (`tracer-offset.py`)

这个Python脚本现在会接受第三个参数（目标模块名），调用Agent的`init`函数，并处理结构化的消息。

```python
# tracer-offset.py
import frida
import sys
import atexit
from collections import defaultdict

# 数据结构:
# { 
#   "site_offset_str": set("target_str_1", "target_str_2") 
# }
CALL_SITES = defaultdict(set)
total_calls_observed = 0
TARGET_MODULE_NAME = ""

def on_message(message, data):
    """消息处理器"""
    global total_calls_observed
    if message['type'] == 'error':
        print(f"[!] Agent Error: {message.get('stack') or message.get('message', 'Unknown error')}")
        return

    if message['type'] == 'send':
        payload = message['payload']
        if payload.get('type') == 'indirect-call':
            site_info = payload['site']
            target_info = payload['target']

            # 我们只关心从目标模块发起的调用
            if site_info['module'] != TARGET_MODULE_NAME:
                return

            site_offset_str = f"0x{int(site_info['offset'], 16):x}"

            # 格式化目标字符串
            if target_info['module']:
                target_str = f"{target_info['module']}!0x{int(target_info['offset'], 16):x}"
            else:
                # 如果目标不在任何已知模块中
                target_str = f"UNK!{target_info['offset']}"
            
            # 如果是新的目标，打印出来
            if target_str not in CALL_SITES[site_offset_str]:
                print(f"[*] New Target: {TARGET_MODULE_NAME}!{site_offset_str} -> {target_str}")

            CALL_SITES[site_offset_str].add(target_str)
            total_calls_observed += 1

def print_results():
    """程序退出时打印最终结果"""
    if not TARGET_MODULE_NAME: return
    
    print("\n" + "="*60)
    print(f"           *** Final Results for {TARGET_MODULE_NAME} ***")
    print("="*60)
    print(f"Total indirect calls observed: {total_calls_observed}")
    print(f"Unique call sites found: {len(CALL_SITES)}")
    
    # 对调用点偏移量进行排序后打印
    for site, targets in sorted(CALL_SITES.items(), key=lambda item: int(item[0], 16)):
        print(f"\n[Call Site] {TARGET_MODULE_NAME}!{site}")
        # 对目标也进行排序，保证输出稳定
        for target in sorted(list(targets)):
            print(f"  -> {target}")
    print("\n" + "="*60)

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python tracer-offset.py <process_name_or_pid> <target_module.so>")
        print("Example (Android): python tracer-offset.py com.example.app libnative-lib.so")
        sys.exit(1)

    target_process = sys.argv[1]
    TARGET_MODULE_NAME = sys.argv[2]
    
    atexit.register(print_results)
    
    try:
        device = frida.get_usb_device(timeout=1)
        print(f"[*] Attaching to '{target_process}' on USB device: {device.name}")
        session = device.attach(target_process)
        
        with open("agent-offset.ts", "r", encoding="utf-8") as f:
            script_code = f.read()
        
        script = session.create_script(script_code)
        script.on('message', on_message)
        
        print("[*] Loading script into the target process...")
        script.load()
        
        # 加载脚本后，通过RPC调用init函数进行初始化
        print(f"[*] Initializing agent for module '{TARGET_MODULE_NAME}'...")
        script.exports.init(TARGET_MODULE_NAME)
        
        print("[*] Initialization complete. Press Ctrl+C to stop and see the results.")
        sys.stdin.read()

    except frida.ProcessNotFoundError:
        print(f"[!] Process '{target_process}' not found. Is it running?")
    except frida.ServerNotRunningError:
        print("[!] Frida server is not running on the device.")
    except Exception as e:
        print(f"[!] An error occurred: {e}")

```

### 如何运行

1.  **保存文件**：将上述代码分别保存为 `agent-offset.ts` 和 `tracer-offset.py`。
2.  **执行命令**：现在你需要提供两个参数：进程名（或包名）和目标SO文件名。

    **示例 (追踪一个Android应用中的 `libnative-lib.so`)**
    ```bash
    python tracer-offset.py com.example.androidapp libnative-lib.so
    ```

### 运行效果

脚本启动后，你会看到类似这样的实时输出，所有地址都已转换为 **模块名!偏移量** 的格式：
```
[*] Attaching to 'com.example.androidapp' on USB device: ...
[*] Loading script into the target process...
[*] Initializing agent for module 'libnative-lib.so'...
[Agent] Initializing for module: libnative-lib.so
[Agent] Found module 'libnative-lib.so' at 0x7a1b2c3000 (size: 65536)
[Agent] Attaching Stalker to all threads...
[Agent] Ready.
[*] Initialization complete. Press Ctrl+C to stop and see the results.
[*] New Target: libnative-lib.so!0x1a2b4 -> libnative-lib.so!0x1c3d4
[*] New Target: libnative-lib.so!0x1a2b4 -> libc.so!0x8e9f0
...
```

当你按 `Ctrl+C` 结束时，会得到清晰的、以偏移量组织的聚合报告：

```
^C
============================================================
           *** Final Results for libnative-lib.so ***
============================================================
Total indirect calls observed: 284
Unique call sites found: 12

[Call Site] libnative-lib.so!0x1a2b4
  -> libnative-lib.so!0x1c3d4
  -> libc.so!0x8e9f0

[Call Site] libnative-lib.so!0x2d3e4
  -> libart.so!0x5a6b7c

...
============================================================
```