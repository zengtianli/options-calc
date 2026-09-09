import SwiftUI

struct UsagePrivacyView: View {
    var body: some View {
        Form {
            Section("用途与使用方法") {
                Text("这是供成年人理解期权结构的离线数学计算工具。选择备兑开仓、现金担保 put、信用价差或铁鹰，输入自己的假设参数，即可查看到期损益、资金占用估算与年化等结果。默认数字仅为计算示例。")
                Text("无需账号或导入文件。修改参数后结果自动更新；手机上可用「只看结果」折起输入，再用「改参数」返回。输入仅在当前运行期间保留，重新启动后恢复默认值。")
            }
            Section("模型与限制") {
                Text("每张合约按 100 股计算，金额以美元显示。损益网格描述假设到期价格下的结果，不是到期前的期权市场报价。")
                Text("盈利概率和期望值 EV 使用零漂移对数正态模型，由现价、隐含波动率和到期天数估算；不预测标的方向，也不保证实际盈利。")
                Text("年化为按 365 天折算的名义指标，不代表一年可以持续获得的收益。距到期时间很短时，年化可能被显著放大。")
                Text("资金占用是按所列结构假设计算的估算值，不是券商实际保证金或购买力报价。融资利率和现金 APY 只用于对应的年化口径；佣金、税费、滑点、提前行权及流动性变化未纳入完整模拟。实际结果可能不同。")
            }
            Section("服务范围") {
                Text("不提供实时行情、证券推荐或个性化投资建议；不连接券商账户，不执行交易，不托管或管理资金。期权交易可能产生重大亏损，请独立核实输入和适用条件。")
                Text("所有四种计算结构均可直接使用，没有注册、用户社区、广告或付费功能解锁；各地区使用相同计算逻辑。")
            }
            Section("隐私") {
                Text("计算在设备本地完成，输入不上传。本应用没有账号、后台服务、第三方分析或广告 SDK，也不把计算参数保存到服务器。无需申请相机、相册、联系人或位置权限。")
                Text("下方网页通过系统浏览器打开，需要网络连接；计算功能不需要联网。访问网站时，网站及其托管服务可能处理 IP 地址等常规网络请求信息，计算参数不会随链接发送。")
                Link("隐私政策（网页）", destination: URL(string: "https://app-ios-options-calc.tianli.cyou/privacy.html")!)
                Link("帮助与联系", destination: URL(string: "https://app-ios-options-calc.tianli.cyou/support.html")!)
            }
            Section("版本") {
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")（\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")）")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("使用说明与隐私")
        .navigationBarTitleDisplayMode(.inline)
    }
}
