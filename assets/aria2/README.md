# assets/aria2

这个目录原本放 `aria2c.exe`（磁力 / BT 引擎）。它属于第三方产物（aria2 项目，GPLv2），
**不随源码仓库分发**，所以克隆下来的仓库里这里是空的，磁力播放会提示引擎缺失。

自行补齐（任选其一）：

1. 从 [aria2/releases](https://github.com/aria2/aria2/releases) 下载 Windows 64 位压缩包，
   把其中的 `aria2c.exe` 放到本目录；
2. 或者把 `aria2c.exe` 所在目录加入 `PATH`（程序优先用随包资源，其次找系统 PATH）。

程序首次使用磁力播放时会把 `aria2c.exe` 释放到应用数据目录下的 `aria2/`，
下载数据与 `.aria2` 控制文件在 `bt/`，可随时整个删除（只影响续传）。
