/**
 * 依赖方插件：声明 inject = ['greeter']，在 greeter 服务就绪前停在 PENDING。
 * 与 greeter.ts 配合演示"书写/挂载顺序无关，激活由服务依赖决定"。
 */
import type { Context } from '@deepseek-ai/cordis'

export const name = 'greeter-consumer'
export const inject = ['greeter']

export function apply(ctx: Context): void {
  console.log(`  [consumer] 激活：ctx.greeter 已就绪 → ${ctx.greeter.greet('consumer')}`)
}
