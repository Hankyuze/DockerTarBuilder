# 使用本项目的方法步骤
## 1、fork 本项目到自己的空间
![1](https://github.com/user-attachments/assets/8bfc9d45-76fb-4cf4-be80-19fb202e8a95)
![2](https://github.com/user-attachments/assets/cf990b0c-a149-4f5b-9be8-d0f909f8f402)
![3](https://github.com/user-attachments/assets/d9560061-4092-4ea2-9b8c-a580c9fdcf2d)
## 2、输入要构建的docker名称和标签
> 如果不输入标签 则默认拉取latest标签,但请确保该镜像有latest <br>
> 如图左侧选项代表要构建的平台。支持amd64、arm64、arm32位三种。<br>
> 若构建的docker镜像小于2GB 推荐发布到release，选择红色框的部分。 绝大多数镜像都是小于2GB的<br>
> 若构建的docker镜像大于2GB 小于5GB 推荐使用另外三个工作流<br>
> 若要构建大于5GB的镜像。本项目不适合。<br>

![4](https://github.com/user-attachments/assets/1a28afc2-2af2-47ff-91fa-0d42282a260a)
![5](https://github.com/user-attachments/assets/5fc5e388-ffb7-4242-aa0e-076136e1e974)
![6](https://github.com/user-attachments/assets/06bf9e37-cfbe-48cc-9012-1c7c92783d6c)
![7](https://github.com/user-attachments/assets/2fb1babf-1179-45fe-a686-2946939e1ac9)

## 3、加载离线docker镜像
`docker load -i xxx.tar.gz` <br>
或 <br>
`docker load < xxx.tar.gz`
> 如果是Artifacts压缩文件 则需要先解压。解压后还是 `tar.gz` 无需再解压 直接load即可。

## 4、可选：构建完成后通过163邮箱接收通知（AMD64 Release工作流）
> `Get-AMD64-Docker-Images-Release` 现支持可选输入 `notify_email`。<br>
> 你可以在运行工作流时填写 `xxx@163.com`，构建完成后会收到包含 Release 下载链接的邮件。<br>
> 注意：镜像文件通常较大，不建议通过邮箱附件发送，推荐邮件里发下载链接。<br>

### 需要提前配置的仓库 Secrets（仅在你要邮件通知时）
- `SMTP_USER`：163邮箱账号（例如 `abc@163.com`）
- `SMTP_PASS`：163邮箱 SMTP 授权码（不是邮箱登录密码）

### 不配置会怎样？
- 如果你不填写 `notify_email`：工作流行为与之前完全一致（只打包并上传到 Releases）。
- 如果你填写了 `notify_email` 但没配 `SMTP_USER/SMTP_PASS`：会跳过邮件发送，并在日志提示，不影响打包和下载。
