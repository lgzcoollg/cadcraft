# 图纸查看站点（DXF/DWG）

一个页面：左边列图纸，右边是真的 CADCraft —— 点开就能缩放、平移、翻图层、量尺寸、导出
PNG/SVG/PDF，中文正常。图纸不进仓库、不传云端，**在你自己的机器/内网里跑**。

两种用法，选一种：

| 用法 | 适合 | 命令 |
|---|---|---|
| **A. 本机 Docker 起一个**（推荐） | 自己和同事在内网看；不想碰 CI | `./serve.sh ~/work/drawings` |
| B. GitLab Pages | 想放到 GitLab 域名下、跟着仓库自动更新 | 见下面「B」一节 |

两种用的是**同一个 `index.html`**：它左边列图纸、右边用 `iframe` 嵌 CADCraft，并通过
`?host=parent` 桥把图纸喂进去（抽屉里那套浏览器 API：`<input type=file>`、下载）。

---

## A. 本机 Docker（不用 CI）

前提：装好 Docker。运行：

```sh
packaging/drawings-viewer/serve.sh ~/work/drawings     # 参数是图纸所在目录
```

它会：

1. 从 `lgzcoollg/cadcraft:0.5.1` 镜像里取出 CADCraft 的 web 版（约 36 MB，**只有第一次慢**，之后复用缓存）
2. 收拢该目录下所有 `.dxf` / `.dwg`，生成清单
3. 起一个容器服务这个站点，端口自动挑空闲的（默认从 8772 起，被占就往后找）

输出会告诉你地址：

```
图纸站点已启动（容器 cadcraft-drawings，镜像 lgzcoollg/cadcraft:0.5.1，站点目录 ~/.cache/cadcraft-drawings-site）
  本机：      http://localhost:8774/
  局域网：    http://10.10.76.167:8774/    （同事用这个）
  停止：      docker rm -f cadcraft-drawings
  换图纸：    再跑一次本脚本
```

常用参数：

```sh
./serve.sh ~/work/drawings --port 9000         # 指定端口
./serve.sh ~/work/drawings --refresh           # 重新从镜像取站点（换了镜像版本之后）
./serve.sh                                     # 不传目录 = 当前目录
CADCRAFT_IMAGE=lgzcoollg/cadcraft:0.5.1 ./serve.sh ~/work/drawings   # 换镜像
```

页面上的操作：

- **左侧**：点图纸打开；顶部搜索框过滤
- **打开本地文件** / **拖放**：临时看自己电脑上的图纸（不上传）
- **Ctrl+S（文件 ▸ 保存）**：内容回传页面 → 变成浏览器**下载**（不会写回你的图纸目录）

注意：

- **局域网访问**用非 `localhost` 地址时是普通 HTTP，WebGPU 不可用（会自动退回 WebGL2，功能照旧，只是渲染路子不同）；`localhost` 没这个限制。
- 图纸目录里最好放你要展示的那一份（比如 `git clone` 下来的仓库目录）。脚本**复制**图纸到缓存站点，不动原目录；看到的是**最后一次运行脚本时**的版本，仓库更新后重跑一次即可。

---

## B. GitLab Pages（可选，跟着仓库自动更新）

想放到 GitLab 域名下、每次 push 自动更新，就用这条。前提是你的项目能用 Pages
（gitlab.com 默认可以；**自建实例需要管理员**配好 Pages，私有项目想只给成员看还需要
`gitlab_pages['access_control'] = true`）。⚠️ **Pages 站点默认公开**，谁能开网址谁就能下载
里面的图纸 —— 私有图纸先确认访问控制。

### 1. 放进你的图纸仓库

```
你的仓库/
├── pages/index.html        ← 把本目录的 index.html 放这里
├── .gitlab-ci.yml          ← 新建（已有就追加下面这段 pages:）
└── …（你的 .dxf / .dwg）
```

### 2. `.gitlab-ci.yml`

```yaml
pages:
  image: lgzcoollg/cadcraft:0.5.1        # 镜像里已经带了站点（/usr/share/nginx/html）
  variables:
    DRAWINGS_DIR: ""                     # 留空 = 收全仓库；也可以写 drawings 只收那个目录
  script:
    - mkdir -p public/viewer public/drawings
    - cp -r /usr/share/nginx/html/. public/viewer/
    - rm -f public/viewer/50x.html
    - cp pages/index.html public/index.html
    - |
      find ${DRAWINGS_DIR:-.} -path ./public -prune -o -type f \
        \( -iname '*.dxf' -o -iname '*.dwg' \) -print \
        | sed 's|^\./||' | sort > public/drawings/index.txt
    - while IFS= read -r f; do mkdir -p "public/drawings/$(dirname "$f")"; cp "$f" "public/drawings/$f"; done < public/drawings/index.txt
    - echo "collected $(wc -l < public/drawings/index.txt) drawing(s)"
  artifacts:
    paths: [public/]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

> job 必须叫 `pages`、产物必须叫 `public/`。这个 job 用 Docker executor；runner 拉不到
> Docker Hub 时要配镜像代理。

### 3. push，然后看 **Deploy ▸ Pages**

网址形如 `https://<命名空间>.gitlab.io/<仓库名>/`，pipeline 跑完才出现。

---

## 常见问题

| 现象 | 处理 |
|---|---|
| `failed to connect to the docker API …` | Docker Desktop 没启动（它休眠/关闭了）。先 `open -a Docker`，等 `docker info` 能通再跑 |
| 页面一直“正在启动 CADCraft…” | 看浏览器控制台是不是 `viewer/…_bg.wasm` 404。本地模式：重跑 `./serve.sh … --refresh`；Pages 模式：确认 CI 的 `cp -r /usr/share/nginx/html/.` 跑了 |
| wasm 的 MIME 不是 `application/wasm` | wasm-bindgen 会自动回退成 ArrayBuffer 加载（能用，稍慢）。Pages 上要根治就让管理员在 NGINX 的 `mime.types` 里确认 `application/wasm wasm;` |
| 清单是空的 | 目录里没有 `.dxf`/`.dwg`，或被 `DRAWINGS_DIR` 限制；本地模式看脚本输出的 `收集到 N 张图纸` |
| Pages 报 `too large archive` | Pages 站点大小超了（自建默认 100 MB，gitlab.com ~1 GB；wasm 本身 36 MB），用 `DRAWINGS_DIR` 只挑需要的目录 |
| 图纸很大很卡 | 浏览器版是单线程 wasm，几十万实体的图纸会慢；建议只放常用的中小图纸 |
| 老图纸文字不对 | web 版不读 SHX 字体（`chineset.shx` 这类），文字用内置字体画；桌面版没这问题 |
| 只想“扫一眼”不要交互 | `cadcraft-cli convert x.dxf x.png`（镜像里就有）出图当 artifact 即可 |

## 协议备忘（想自己嵌到别的页面时）

父页与 iframe 必须**同源**。消息：

| 方向 | 消息 | 载荷 |
|---|---|---|
| 子页 → 父页 | `cadcraft:ready` | `{version}` |
| 父页 → 子页 | `cadcraft:open` | `{name, bytes}`（`ArrayBuffer`/`Uint8Array`） |
| 子页 → 父页 | `cadcraft:save` | `{name, bytes}`（transferable），Save/Save As/导出都走它 |
| 子页 → 父页 | `cadcraft:dirty` / `cadcraft:failed` | `{dirty}` / `{error}` |

实现见 `apps/cadcraft-web/src/host.rs`。
