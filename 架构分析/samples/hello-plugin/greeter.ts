/**
 * 一个最小的真实 Cordis 插件：认领 ctx.greeter 服务、声明自定义类型化事件、
 * 注册可逆效果。写法与 dsh 产品插件（如 dsh-repeat-tool-reminder）完全同构。
 */
import { Service } from '@deepseek-ai/cordis'
import type { Context } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'

// ① 声明合并：把自定义事件与服务键焊进框架类型（不改框架源码一个字）
declare module '@deepseek-ai/cordis' {
  interface Events {
    'greeter/hello'(who: string): void
  }
  interface Context {
    greeter: Greeter
  }
}

export const name = 'greeter'

// ② 插件配置：Schemastery schema 校验 + 默认值（进 apply 之前已完成）
export interface Config {
  greeting?: string
}
export const Config: z<Config> = z.object({
  greeting: z.string().default('你好'),
})

// ③ Service 子类：super(ctx, 'greeter') 构造即认领 ctx 键，随 fiber 卸载自动注销
export class Greeter extends Service {
  constructor(ctx: Context, private readonly config: Config) {
    super(ctx, 'greeter')
  }
  greet(who: string): string {
    return `${this.config.greeting}, ${who}!`
  }
}

// ④ 插件主体（函数形态）：一切注册经 ctx.on / ctx.effect，各返回拆除器
export function apply(ctx: Context, config: Config): void {
  const greeter = new Greeter(ctx, config)

  // 注册即效果 1：类型化事件监听（on 返回退订函数）
  ctx.on('greeter/hello', (who) => {
    console.log(`  [greeter] 事件到达 greeter/hello(${who}) → ${greeter.greet(who)}`)
  })

  // 注册即效果 2：任意可逆资源——返回清理函数，fiber 卸载时逆序执行
  const handle = setInterval(() => {}, 2 ** 30)
  ctx.effect(() => () => {
    clearInterval(handle)
    console.log('  [greeter] 效果拆除：定时器已清理')
  })
}
