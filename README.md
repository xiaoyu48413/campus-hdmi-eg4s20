# 基于安路 EG4S20 的校园 HDMI 多媒体展示系统

本仓库是 HX4S20C 开发板上已验证的工程。工程以康芯/安路提供的例程为基础扩展。

## 工程内容

- `src/user_source/hdl_source/`：Verilog 源码、字模和相关硬件模块。
- `src/user_source/constraints_source/`：引脚及时序约束。
- `src/td_project/HDMI1.4b_Transmitter_v1.0.al`：Tang Dynasty 工程入口。
- `src/td_project/al_ip/`：工程使用的 IP 文件。
- `verification/`：仿真测试源文件。
- `release/anlu1.bit`：已生成的下载位流；`release/` 还包含资源与时序报告。

支持 320×240、640×480 的 24 位非压缩 BMP 图片和 TF 卡中的 PCM WAV 音乐。图片最多十张，支持手动切换、自动轮播、滚动字幕与板载按键菜单。

使用 Tang Dynasty 6.2 打开 `.al` 工程。工程文件保留原开发机绝对路径，换电脑后如软件提示原目录，请将工程保存到本地目录；源文件引用采用相对路径。TF 卡素材未收录在仓库中。

更详细的操作说明见 [上传与使用说明.txt](上传与使用说明.txt)。
