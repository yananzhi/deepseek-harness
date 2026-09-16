/**
 * 宿主侧：不用 Loader，直接用 Context API 完整走一遍
 * 注册（ctx.plugin）→ 生效（inject 就绪 / 服务可用 / 事件流动）→ 注销（fiber.dispose）。
 * 运行：npx tsx run.ts（在本文档所在目录）
 */
import { Context } from '@deepseek-ai/cordis'
import * as greeter from './greeter.ts'
import * as consumer from './consumer.ts'

// FiberState 是数字枚举，转成可读名
const state = (f: { state: number }) =>
  (['PENDING', 'LOADING', 'ACTIVE', 'FAILED', 'DISPOSED', 'UNLOADING'] as const)[f.state]

const ctx = new Context()

console.log('1) 注册：先挂"有依赖的一方"（顺序故意写反，演示 inject 等待）')
const consumerFiber = ctx.plugin(consumer, {})
console.log(`   consumer fiber 已创建，state=${state(consumerFiber)} —— 在等 greeter 服务出现`)

console.log('2) 生效：挂上 greeter（配置先过 Schemastery 校验，缺省字段补默认值）')
const greeterFiber = await ctx.plugin(greeter, { greeting: '早上好' })
await consumerFiber
console.log(`   greeter state=${state(greeterFiber)}, consumer state=${state(consumerFiber)}`)
console.log(`   服务调用 ctx.greeter.greet('世界') → ${ctx.greeter.greet('世界')}`)
console.log('   派发事件 ctx.emit("greeter/hello", "Fiber")')
ctx.emit('greeter/hello', 'Fiber')

console.log('3) 注销：dispose greeter fiber，效果按注册逆序拆除')
await greeterFiber.dispose()
console.log(`   greeter state=${state(greeterFiber)} —— ctx.greeter 已注销，consumer 回到 ${state(consumerFiber)}`)
if (consumerFiber.state !== 4) {
  await consumerFiber.dispose()
  console.log(`   consumer state=${state(consumerFiber)} —— 全部拆除，进程可干净退出`)
}
