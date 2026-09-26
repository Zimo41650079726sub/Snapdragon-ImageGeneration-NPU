# SIGN — Snapdragon-ImageGeneration-NPU

**Snapdragon X Elite の NPU で stable-diffusion.cpp を動かす。** 名前のとおり、NPU 側は Microsoft 署名（signed）済みのライブラリを使うので、テスト署名は要りません。

Snapdragon X Elite のノート PC を買ったのに、画像生成がとても遅い。そう感じている人のための手順とスクリプトです。

Snapdragon X Elite には NPU（AI 処理用のチップ、Hexagon NPU v73）が載っていますが、ふつうの画像生成ソフトは CPU で計算するので、NPU は使われないままです。この手順では、Windows on Snapdragon で [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) の拡散モデル本体（DiT）を **NPU（Hexagon HTP）で実行**し、CPU だけのときより **約 2.5〜2.7 倍速く**します。

- 対象：Windows 11 ARM64 のノート PC（Snapdragon X Elite / X Plus）
- **テストモードや Secure Boot の無効化は不要**です。NPU 側のライブラリには、Qualcomm の [GenieX](https://github.com/qualcomm/GenieX) SDK に同梱されている **Microsoft 署名済み**のものを使います（スクリプトが公式リリースからダウンロードし、チェックサムと署名を確認します）。
- PC 側（sd.cpp と llama.cpp の ggml-hexagon）は、その NPU ライブラリと対になる版をソースからビルドします。
- プログラムを書く必要はありません。コマンドをコピーして貼り付けるだけです。管理者権限も要りません。
- 使い方はコマンドライン（PowerShell）が基本です。ブラウザの画面から使うこともできます（[ブラウザから使う](#ブラウザから使う)）。
- ビルドは 10〜15 分です（このほか、SDK とソースのダウンロード時間がかかります）。

**ページ内の案内**：[どれくらい速くなるか](#どれくらい速くなるか) ／ [必要なもの](#必要なもの) ／ [モデルの入手先](#モデルの入手先) ／ [手順](#手順) ／ [トラブルシューティング](#トラブルシューティング) ／ [アンインストール](#アンインストール)

## どれくらい速くなるか

Dell XPS 13 9345（Snapdragon X Elite X1E80100、RAM 64GB）、通常の Windows での実測です。512×512、同じプロンプトで、NPU と CPU を 2 回ずつ測った範囲です（詳しい条件は[計測条件の詳細](#計測条件の詳細)）。

| モデル（Q4_0） | ステップ | NPU（この手順） | CPU（WSL2、12 スレッド） | NPU の速さ |
|---|---:|---:|---:|---:|
| FLUX.2 klein 4B | 4 | **50.5〜52.3 秒**（DiT 34.8〜36.6 秒） | 117.4〜137.1 秒（DiT 97.3〜98.8 秒） | 約 2.5 倍 |
| Z-Image-Turbo | 8 | **87.5〜91.7 秒**（DiT 75.8〜79.0 秒） | 238.8〜239.9 秒（DiT 213.7〜215.7 秒） | 約 2.7 倍 |
| Krea2-Turbo-HD | 8 | **249.5〜252.0 秒**（DiT 226.0〜234.4 秒） | 629.9〜645.7 秒（DiT 597.3〜613.7 秒） | 約 2.5 倍 |

時間は 1 枚あたりの合計です。NPU で計算しているのは DiT だけで、テキストエンコーダ（TE）と VAE は CPU です。

### 生成例

プロンプト（3 モデル共通）：

```
A cute cat sitting in front of a small closed Japanese shop, a hand-written paper sign on the shutter that says "臨時休業", warm evening light, photo
```

| Z-Image-Turbo（NPU、8 ステップ） | Krea2-Turbo-HD（NPU、8 ステップ） |
|:---:|:---:|
| ![Z-Image-Turbo](images/zimage_npu.png) | ![Krea2-Turbo-HD](images/krea2_npu.png) |
| 「臨」がわずかに崩れた | 「臨」がわずかに崩れた |

FLUX.2 klein 4B の CPU 版と NPU 版です。構図は同じですが、窓や小物などの細部が違います（理由は[計測条件の詳細](#計測条件の詳細)）。klein は漢字を正しく描けないモデルです。

| CPU（117.4 秒） | NPU（50.5 秒） |
|:---:|:---:|
| ![klein CPU](images/klein_cpu.png) | ![klein NPU](images/klein_npu.png) |

画像の PNG にはプロンプトと生成条件が埋め込まれています。

## 必要なもの

### 対応する PC

- Windows 11 ARM64 のノート PC（Snapdragon X Elite / X Plus）
- GenieX のライブラリは v73 / v75 / v79 / v81 の 4 世代分ありますが、**確認したのは v73（X Elite）だけ**です。

### メモリ

生成中に PC 全体で増えたメモリのピークです。**32GB の PC なら、どのモデルも余裕を持って動きます。**

| モデル | 増えたメモリ（ピーク） | モデルファイルの合計（DiT＋TE＋VAE） |
|---|---:|---:|
| FLUX.2 klein 4B | 5.8 GB | 4.7 GB |
| Z-Image-Turbo | 7.4 GB | 5.8 GB |
| Krea2-Turbo-HD | 11.1 GB | 9.2 GB |

目安は「モデルファイルの合計＋1.5〜2GB」です。sd-cli のプロセス単体の数字（1.5〜2.0GB）は、NPU との共有メモリが含まれないため小さく出ます。16GB の PC でも klein と Z-Image は動く見込みですが、確認していません。

### ディスク容量

| もの | 置き場所 | 大きさ |
|---|---|---:|
| Hexagon SDK | `C:\Qualcomm\Hexagon_SDK` | ダウンロード 約 818MB、展開後 約 3.25GB |
| 作業フォルダ（llama.cpp と stable-diffusion.cpp のソース、GenieX SDK、ビルド成果物） | `%USERPROFILE%\snapdragon-npu-work` | 約 1.4GB |
| モデルファイル | 好きな場所（`-ModelDir` で指定） | 1 モデルあたり 4.7〜9.2GB（上の表） |
| Visual Studio などのツール | 各ツールの既定の場所 | <!-- TODO: 作者が記入 --> |

Hexagon SDK と作業フォルダの大きさは、作者の PC での実測です（作業フォルダは、ブラウザ用の画面もビルドした状態）。

### ソフトウェア

[手順 0](#0-準備ツールの導入) で入れます。

- Visual Studio 2026（Community で可）と ARM64 用の C++ ビルドツール
- LLVM、CMake、Ninja、Git、Python（ARM64 版）
- （ブラウザから使う場合のみ）Node.js と pnpm。**ないと、ブラウザ用の画面はビルドされません**（sd-cli での生成には影響しません）。

### モデルの入手先

モデルファイルは、1 つのフォルダにまとめて置きます。

**klein と Z-Image は、動作確認に使ったファイル一式を [Zimo4165/SIGN-models](https://huggingface.co/Zimo4165/SIGN-models) に置いてあります**（Apache-2.0）。次の 1 行で、`C:\sd-models` にまとめて入ります（約 8.9GB）。生成するときは `-ModelDir C:\sd-models` を指定してください。

```powershell
hf download Zimo4165/SIGN-models --local-dir C:\sd-models
```

`hf` コマンドがない場合は、先に `pip install -U huggingface_hub` を実行してください。ブラウザで 1 ファイルずつダウンロードしても構いません。

Krea2 と Qwen-Image-2.1 の入手先は、stable-diffusion.cpp の各モデルの説明文書（固定コミット `c92d73c`）に書かれているものです。

| `-Model` | 拡散モデル | テキストエンコーダ | VAE | 既定ステップ |
|---|---|---|---|---:|
| `klein` | `flux-2-klein-4b-Q4_0.gguf` | `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` | `flux2-vae.safetensors` | 4 |
| `zimage` | `z-image-turbo-Q4_0.gguf` | `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` | `ae.safetensors` | 8 |
| `krea2` | `Krea2-Turbo-HD-V1-Q4_0.gguf` | `Qwen3-VL-4B-Instruct-Uncensored-abliterated.Q4_0.gguf` | `wan_2.1_vae.safetensors` | 8 |
| `qwen21` | `qwen_image_2.1-Q4_0.gguf` | `Qwen3VL-8B-Instruct-Q4_K_M.gguf` | `qwen_image_2.1_vae_bf16.safetensors` | 20 |

**FLUX.2 klein 4B**（[sd.cpp の説明](https://github.com/leejet/stable-diffusion.cpp/blob/c92d73c408515c94beef32161bb5960764fde7a0/docs/flux2.md)）

- 拡散モデル：[Zimo4165/SIGN-models](https://huggingface.co/Zimo4165/SIGN-models) の `flux-2-klein-4b-Q4_0.gguf`。[unsloth/FLUX.2-klein-4B-GGUF](https://huggingface.co/unsloth/FLUX.2-klein-4B-GGUF) の Q4_K_M を Q4_0 に変換したものです。[leejet/FLUX.2-klein-4B-GGUF](https://huggingface.co/leejet/FLUX.2-klein-4B-GGUF) の Q4_0 は同じ名前ですが別のファイルで、NPU では確認していません。
- テキストエンコーダ：`Qwen3-4B-Instruct-2507-Q4_K_M.gguf`（SIGN-models に同梱。元は [unsloth/Qwen3-4B-Instruct-2507-GGUF](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF) の無改変ファイル）。sd.cpp の説明では `unsloth/Qwen3-4B-GGUF` が挙がっています。この手順では Instruct-2507 版で確認しました。
- VAE：`flux2-vae.safetensors`（SIGN-models に同梱）

**Z-Image-Turbo**（[sd.cpp の説明](https://github.com/leejet/stable-diffusion.cpp/blob/c92d73c408515c94beef32161bb5960764fde7a0/docs/z_image.md)）

- 拡散モデル：[Zimo4165/SIGN-models](https://huggingface.co/Zimo4165/SIGN-models) の `z-image-turbo-Q4_0.gguf`。[unsloth/Z-Image-Turbo-GGUF](https://huggingface.co/unsloth/Z-Image-Turbo-GGUF) の Q4_K_M（2025 年 12 月版）を Q4_0 に変換したものです。
- テキストエンコーダ：klein と同じ `Qwen3-4B-Instruct-2507-Q4_K_M.gguf`
- VAE：`ae.safetensors`（SIGN-models に同梱。元は [black-forest-labs/FLUX.1-schnell](https://huggingface.co/black-forest-labs/FLUX.1-schnell)）。Z-Image は **FLUX.1 の VAE をそのまま使います**。klein 用の `flux2-vae.safetensors`（FLUX.2 の VAE）とは別物なので、取り違えないでください。

**Krea2-Turbo-HD**（[sd.cpp の説明](https://github.com/leejet/stable-diffusion.cpp/blob/c92d73c408515c94beef32161bb5960764fde7a0/docs/krea2.md)）

- 拡散モデル：`Krea2-Turbo-HD-V1-Q4_0.gguf` <!-- TODO: 作者が記入（入手先） -->。sd.cpp の説明にある Krea-2 Turbo の GGUF（[realrebelai/KREA-2_GGUFs](https://huggingface.co/realrebelai/KREA-2_GGUFs) の `TURBO/`）には Q4_0 がなく、Q4_K_M などで NPU が動くかは確認していません。
- テキストエンコーダ：この手順では `Qwen3-VL-4B-Instruct-Uncensored-abliterated.Q4_0.gguf` で確認しました <!-- TODO: 作者が記入（入手先） -->。sd.cpp の説明では、通常版の [Qwen/Qwen3-VL-4B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF)（`Qwen3VL-4B-Instruct-Q4_K_M.gguf`）が指定されています。**ただし通常版では、NPU で生成すると横帯のノイズが出ます**（CPU では正常。Q4_0 に変換しても直りません）。原因は調査中です（[既知の問題](#既知の問題)）。
- VAE：[Comfy-Org/Wan_2.1_ComfyUI_repackaged](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged) の `split_files/vae/wan_2.1_vae.safetensors`

**Qwen-Image-2.1**（[sd.cpp の説明](https://github.com/leejet/stable-diffusion.cpp/blob/c92d73c408515c94beef32161bb5960764fde7a0/docs/qwen_image_2.1.md)）。NPU では帯状のノイズが出るので、今は `-Cpu` で使ってください（[既知の問題](#既知の問題)）。

- 拡散モデル：[leejet/Qwen-Image-2.1-GGUF](https://huggingface.co/leejet/Qwen-Image-2.1-GGUF) の `qwen_image_2.1-Q4_0.gguf`
- テキストエンコーダ：[Qwen/Qwen3-VL-8B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF) の `Qwen3VL-8B-Instruct-Q4_K_M.gguf`
- VAE：[Comfy-Org/Qwen-Image-2.1](https://huggingface.co/Comfy-Org/Qwen-Image-2.1) の `vae/qwen_image_2.1_vae_bf16.safetensors`

**拡散モデルは Q4_0 を使ってください。** NPU の行列演算（HMX）が扱える重みの型は Q4_0 / Q4_1 / Q8_0 / Q4_K / Q6_K / IQ4_NL / MXFP4 / F16 / F32 です（llama.cpp のソースで確認）。Q4_0 で動作と速度を確認しています。

## 手順

### 0. 準備：ツールの導入

PowerShell で次を実行します（すでに入っているものは不要です）。

```powershell
winget install LLVM.LLVM
winget install Kitware.CMake
winget install Ninja-build.Ninja
winget install Git.Git
winget install Python.Python.3.12 --architecture arm64
```

Visual Studio 2026（Community で可）は Visual Studio Installer から入れ、「C++ によるデスクトップ開発」と **ARM64 用の MSVC ビルドツール**を選びます。

ブラウザから使いたい場合は、Node.js と pnpm も入れます。**ビルド（手順 2）の前に**入れてください。

```powershell
winget install OpenJS.NodeJS.LTS
npm install -g pnpm
```

`npm` が見つからないと表示されたら、PowerShell を開き直してから 2 行目を実行してください。

このリポジトリを取得し、スクリプトを実行できるようにします。スクリプトは署名されていないので、**PowerShell を開くたびに**実行ポリシーを一時的に緩めます。

```powershell
git clone https://github.com/Zimo41650079726sub/SIGN-Snapdragon-ImageGeneration-NPU.git
cd SIGN-Snapdragon-ImageGeneration-NPU
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\00-check.ps1
```

`00-check.ps1` は現状を表示するだけで、何も変更しません。以降の手順の進み具合もこれで確認できます。管理者権限は、どの手順でも不要です。

### 1. ソースと NPU ライブラリの取得

作業フォルダは既定で `%USERPROFILE%\snapdragon-npu-work` です（環境変数 `SNPU_WORK` で変更できます）。

```powershell
.\scripts\20-get-sources.ps1
```

次のことを行います。

- llama.cpp と stable-diffusion.cpp を固定コミットで取得し、パッチを当てる（GenieX のパッチは GenieX の公式リポジトリから取得し、SHA256 を照合）
- Hexagon SDK を `C:\Qualcomm` に導入（ダウンロード 約 818MB、展開後 約 3.25GB）
- GenieX v0.7.0 の SDK（約 85MB）を公式リリースからダウンロードし、SHA256 を照合して展開。NPU ライブラリのカタログに Microsoft の署名があることを確認

### 2. ビルド

```powershell
.\scripts\30-build.ps1   # 10〜15 分。ログは作業フォルダの build-npu.log
```

### 3. 生成

モデルファイルを 1 つのフォルダにまとめて置き、`-ModelDir` で指定します（ファイル名と入手先は[モデルの入手先](#モデルの入手先)）。

```powershell
.\scripts\50-generate.ps1 -Model klein -ModelDir D:\sd-models -Prompt "a lovely cat" -Out cat.png
```

ファイル名が違う場合は `-Diffusion` / `-Llm` / `-Vae` で個別に指定できます。`-Cpu` を付けると同じ条件で CPU だけで実行します（比較用）。ほかの指定は[50-generate.ps1 の引数](#50-generateps1-の引数)にあります。

## 使い方の詳細

### 50-generate.ps1 の引数

| 引数 | 既定値 | 説明 |
|---|---|---|
| `-Model` | `klein` | `klein` / `zimage` / `krea2` / `qwen21`。ファイル名と既定のステップ数・ガイダンスが決まります |
| `-ModelDir` | `%USERPROFILE%\sd-models` | モデルファイルを置いたフォルダ |
| `-Prompt` | `a lovely cat` | プロンプト |
| `-Width` / `-Height` | `512` / `512` | 画像の幅と高さ |
| `-Steps` | モデルごと（4 / 8 / 8 / 20） | ステップ数。0 ならモデルの既定値 |
| `-Seed` | `42` | シード |
| `-Out` | 今いるフォルダの `output.png` | 保存先のファイル名 |
| `-Diffusion` / `-Llm` / `-Vae` | `-ModelDir` と `-Model` から決まる | ファイルを個別に指定するとき |
| `-Cpu` | なし | 付けると同じ条件で CPU だけで実行（比較用） |
| `-Threads` | CPU の論理コア数 | CPU で計算する部分のスレッド数 |

- **ネガティブプロンプトは未対応**です（このスクリプトには指定する引数がありません）。
- CFG とガイダンスはモデルごとに固定です（klein：CFG 1、Z-Image：CFG 1・ガイダンス 3.5、Krea2：CFG 1・ガイダンス 1.0、Qwen-Image-2.1：CFG 6.0）。

### NPU で動いているか確かめる

生成中に表示されるログで分かります。NPU が使われていると、次の 2 行が出ます。

```
[INFO   ] ggml - ggml-hex: HTP0 new session : session-id 0 domain-id 3 uri file:///libggml-htp-v73.so?...
[INFO   ] ggml - ggml-hex: HTP0 power mode: burst
```

`libggml-htp-v73.so` の `v73` は NPU の世代です（X Elite は v73）。あわせて `Using flash attention in the diffusion model` が出ていれば、flash attention も有効です（この行は CPU のときにも出ます）。

- `failed to open session: 0x80000406` が出た場合は、NPU ライブラリの署名が受け付けられていません（[トラブルシューティング](#トラブルシューティング)）。
- 同じ条件で `-Cpu` を付けて生成し、時間を比べる方法もあります。[どれくらい速くなるか](#どれくらい速くなるか)の表くらいの差があれば、NPU で動いています。

### sd-cli / sd-server を直接使う場合

スクリプトがしていることは次のとおりです。sd-server など、ほかの使い方でも同じ設定が必要です。

```powershell
# 署名済みの NPU ライブラリの場所（PATH には入れない。GenieX 版の ggml DLL も入っているため）
$env:ADSP_LIBRARY_PATH = "<作業フォルダ>\geniex-sdk-v0.7.0\sdk-windows-arm64\lib\llama_cpp"
$env:GGML_HEXAGON_OPFILTER = "CONCAT|CONT"   # 遅い演算を CPU へ
<作業フォルダ>\stable-diffusion.cpp\build-npu\bin\sd-cli.exe ... `
    --backend "diffusion=HTP0,te=cpu,vae=cpu" `
    --params-backend "diffusion=HTP0,te=cpu,vae=cpu" --auto-fit off --diffusion-fa
```

NPU は空きメモリを 0 MiB と報告するため、自動配置（auto-fit）に任せると重みが CPU 側に置かれて動きません。`--params-backend` と `--auto-fit off` で明示してください。flash attention（`--diffusion-fa`）なしでは 3 倍以上遅くなります。

### ブラウザから使う

sd-server を起動すると、ブラウザから生成できます。ビルドの前に Node.js と pnpm を入れておく必要があります（[手順 0](#0-準備ツールの導入)）。

klein の例です。`D:\sd-models` はモデルを置いたフォルダに置き換えてください。

```powershell
$W = "$env:USERPROFILE\snapdragon-npu-work"
$M = "D:\sd-models"
$env:ADSP_LIBRARY_PATH = "$W\geniex-sdk-v0.7.0\sdk-windows-arm64\lib\llama_cpp"
$env:GGML_HEXAGON_OPFILTER = "CONCAT|CONT"
& "$W\stable-diffusion.cpp\build-npu\bin\sd-server.exe" `
    --diffusion-model "$M\flux-2-klein-4b-Q4_0.gguf" --llm "$M\Qwen3-4B-Instruct-2507-Q4_K_M.gguf" --vae "$M\flux2-vae.safetensors" `
    --backend "diffusion=HTP0,te=cpu,vae=cpu" --params-backend "diffusion=HTP0,te=cpu,vae=cpu" --auto-fit off --diffusion-fa
```

起動したら、ブラウザで http://127.0.0.1:1234/ を開きます（sd-server の既定のポートは 1234 で、`--listen-port` で変えられます）。止めるときは、PowerShell で Ctrl+C を押します。

## 既知の問題

- **Qwen-Image-2.1 で画像の横一列に帯状のノイズが出る**：署名済み構成と付録 A の構成の両方で、ステップ数（20 / 30）に関係なく同じ位置に同じ形で出ました。NPU ライブラリの版によらないので、両方に共通する部分に原因があると見ていますが、未特定です。Qwen-Image-2.1 は当面 `-Cpu` で使ってください（NPU では 1 枚 659 秒、メモリの増加は 11.2GB でした）。
  - 同じ形の帯は、**Krea2 のテキストエンコーダを通常版の Qwen3-VL-4B-Instruct にしたとき**にも出ます。abliterated 版では出ず、CPU ではどちらも正常です。テキストエンコーダの出力の中身によって、NPU 側の計算（FP16）があふれている可能性があります。
- **NPU の CONCAT / CONT が遅い**：`GGML_HEXAGON_OPFILTER` で CPU に回して回避しています。
- **VAE と TE は CPU**：NPU にも載せられますが、現状は逆効果です（付録 A の構成、klein、512²）。
  - TE を NPU（`te=HTP0`）：7.1 秒（CPU は約 4 秒）。画像は正常ですが、FP16 計算のため細部が変わります
  - VAE を NPU（`vae=HTP0`）：53.4 秒（CPU は約 10 秒）。さらに縦線状のノイズが出ます
- **GenieX の版に縛られる**：PC 側は GenieX 同梱の NPU ライブラリと同じ版（llama.cpp `4ff829e` + GenieX のパッチ）でビルドする必要があります。GenieX が更新されたら、`scripts/common.ps1` の版とチェックサムを合わせます。

## トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| `failed to start session: 0x8000040e` | PC 側と NPU ライブラリの版の不一致。`20-get-sources.ps1` を再実行してから再ビルド |
| `failed to open session: 0x80000406` | 署名が受け付けられていない。自己署名のライブラリを通常モードで使おうとしている（`ADSP_LIBRARY_PATH` を確認） |
| `dspqueue_read failed: 0x00000072` | NPU 側の異常終了。パッチが当たっていない、または sd.cpp 同梱の古い ggml でビルドした |
| アクセス違反 `0xC0000005` で終了 | in-place 演算の問題。`20-get-sources.ps1` がパッチを当てているか確認 |
| ビルドで `UnicodeDecodeError: 'cp932' codec` | 日本語版 Windows の Python の既定文字コード。スクリプトは `PYTHONUTF8=1` を設定済み |
| リンクで `mkvmuxer::...` が未定義 | libwebm。スクリプトは `-DSD_WEBM=OFF` を指定済み |
| `SHA256 mismatch` | ダウンロードの破損、または上流のファイルが変わった。再実行して直らなければ版を確認 |
| NPU を指定したのに速くならない | `ADSP_LIBRARY_PATH` の指定漏れ、または量子化型が Q4_0 などでない。[NPU で動いているか確かめる](#npu-で動いているか確かめる)を参照 |
| 作業フォルダを移動・改名したら、ビルドが失敗する | ビルドの記録に古い場所が残っている。作業フォルダの中の `stable-diffusion.cpp\build-npu` と `stable-diffusion.cpp\examples\server\frontend\node_modules` を削除してから、`30-build.ps1` を実行し直す |
| sd-server を開いてもブラウザに画面が出ない（ビルドのログに `pnpm not found; frontend build disabled`） | ビルドのときに pnpm がなかった。Node.js と pnpm を入れ（[手順 0](#0-準備ツールの導入)）、`stable-diffusion.cpp\build-npu` を削除してから `30-build.ps1` を実行し直す |

## 技術解説

### 計測条件の詳細

- PC：Dell XPS 13 9345（Snapdragon X Elite X1E80100、RAM 64GB）、**Secure Boot オン・テスト署名オフ（通常の Windows）**
- 512×512、seed 42、すべて同じプロンプト。NPU と CPU を NPU→CPU→CPU→NPU の順に 2 回ずつ、各回の前に 120 秒休ませて測り、範囲で示します。
- 時間は 1 枚あたりの合計（テキストエンコーダ・DiT・VAE）です。NPU で計算しているのは DiT だけで、テキストエンコーダ（TE）と VAE は CPU です。
- CPU の比較対象は、WSL2 上の stable-diffusion.cpp（12 スレッド）です。同じスレッド数なら、Windows ネイティブ版より WSL2 版の方が 13〜19% 速かったため、速い方と比べています。
- Krea2 は、GenieX 版の NPU ライブラリで落ちる大きな行列積を CPU に回しているため、倍率が伸びにくくなっています（下の「何が効いたか」）。
- NPU 側を自分でビルドした新しい版にすると、さらに速くなります（klein の DiT 23〜25 秒、Krea2 の DiT 約 92 秒）。ただしテストモードが必要です（付録 A）。
- 生成例の klein の CPU 版は、比較対象の WSL2 版（ビルドが別）で作ったもので、NPU の FP16 計算による差と、ビルドの違いによる差の両方を含みます。同じビルドで CPU と NPU を比べたときの差は、画素あたり平均 1.7/255 でした。

### 何が効いたか

NPU 上の処理時間を演算ごとに測ると（`GGML_HEXAGON_PROFILE=1`）、行列積は全体の 3% しかなく、最大の行列積で約 10.6 TFLOPS 出ていました。遅さの原因は計算ではなく、データを複製・連結・並べ替える演算でした。

| 対策 | 内容 | 効果（512²、1 ステップの DiT、付録 A の構成で計測） |
|---|---|---:|
| なし | | 34.7 秒 |
| RoPE の書き換え（`patches/sdcpp-rope-no-repeat.patch`） | 最内次元が 1 のテンソルを複製する REPEAT（NPU 上で 0.1 GB/s、時間の 57%）をなくした。出力はビット単位で同一 | 19.4 秒 |
| CONCAT / CONT を CPU で実行（`GGML_HEXAGON_OPFILTER=CONCAT\|CONT`） | NPU 上のコピー・並べ替えが 0.1〜0.3 GB/s と遅いため | **7.4 秒** |
| （参考）CPU のみ | | 22.2 秒 |

このほか、NPU が落ちる問題を回避しています。

| 症状 | 原因 | 対策 |
|---|---|---|
| ホスト側のアクセス違反（`0xC0000005`） | CPU で計算されたテンソルへの in-place 演算が NPU に割り当てられる | `patches/llama.cpp-ggml-hexagon-inplace-view-src.patch` |
| 開始時に `failed to start session: 0x8000040e` | GenieX の NPU ライブラリは上流 llama.cpp に独自パッチ（電力モード等）を当てたもので、通信の定義が違う | GenieX の公開パッチ 3 本を PC 側にも当てる（スクリプトが自動で取得） |
| DSP 側の異常終了（`dspqueue_read failed: 0x72`） | GenieX 版（llama.cpp `4ff829`）の要素ごとの演算は、行が詰まっていない入力（SwiGLU の gate/up）で落ちる | `patches/llama.cpp-ggml-hexagon-geniex-4ff829-workarounds.patch` で該当する演算だけ CPU へ |
| 同上（Krea2 の 512² 以上） | GenieX 版の行列積は、内側の次元が大きく（K=16384）トークンが多いと落ちる | 同じパッチで K>12288 かつ 264 トークン超の行列積だけ CPU へ |
| DSP 側の異常終了（`0x72`、別原因） | stable-diffusion.cpp 同梱の ggml は Hexagon バックエンドが古い | llama.cpp の ggml を使ってビルドする |

### 動作確認環境

| 項目 | バージョン |
|---|---|
| PC | Dell XPS 13 9345（Snapdragon X Elite X1E-80-100） |
| OS | Windows 11 Home 10.0.26200（ARM64）、Secure Boot オン |
| NPU ドライバ | 30.0.220.3000 |
| Visual Studio | 2026 Community 18.4（MSVC ARM64） |
| LLVM | clang（`winget install LLVM.LLVM`） |
| Hexagon SDK | 6.6.0.0（llama.cpp の `setup-sdk.py` で導入。PC 側のビルドに必要） |
| GenieX SDK | v0.7.0（NPU 側の Microsoft 署名済みライブラリ） |
| llama.cpp | `4ff829e`（GenieX v0.7.0 と同じ版。ggml のみ使用） |
| stable-diffusion.cpp | `c92d73c` |

---

## 付録 A：NPU ライブラリを自分でビルド・署名する（上級者向け、テストモードが必要）

新しい llama.cpp（`e6ab7c1`）から NPU ライブラリを自分でビルドすると、DiT が約 1.4 倍速くなります（klein 512²・4 ステップで DiT 23〜25 秒）。ただし自分で署名したライブラリは、**テストモードでしか読み込まれません**。

> [!WARNING]
> テストモードにするには **Secure Boot の無効化**が必要で、PC のセキュリティが下がります。BitLocker が有効な PC では、手順を誤ると**回復キーの入力を求められ**ます。NPU 側を改造したい人以外は、メインの手順を使ってください。

1. BitLocker の回復キー（48 桁）を控え、`manage-bde -protectors -get C:` の ID と一致することを確認する
2. 管理者の PowerShell で `Suspend-BitLocker -MountPoint C: -RebootCount 0`
3. BIOS で Secure Boot を無効にし、`bcdedit /set testsigning on` → 再起動（右下に「テスト モード」）
4. `winget install --id Microsoft.WindowsWDK.10.0.26100 -e`（inf2cat のため）
5. 管理者の PowerShell で `.\scripts\10-make-cert.ps1`（自己署名の証明書を作成し、信頼済みに登録）
6. `Resume-BitLocker -MountPoint C:`
7. 以降は `$env:SNPU_MODE = 'self-signed'` を設定してから `20-get-sources.ps1` → `30-build.ps1` → `40-sign-htp.ps1`（pfx のパスワードを入力）→ `50-generate.ps1`

署名用の秘密鍵（`%USERPROFILE%\Certs\ggml-htp-v1.pfx` と `.pvk`）は、署名が終わったら **USB メモリなど PC の外へ移し**、PC からは完全に削除してください（ごみ箱に残さない）。この鍵を持つ人は、この PC が信頼するコードを作れてしまいます。

### 元に戻すとき

`bcdedit /set testsigning off` → `certlm.msc` で「信頼されたルート証明機関」と「信頼された発行元」から `GGML.HTP.v1` を削除 → BitLocker を一時停止 → BIOS で Secure Boot を有効化 → `Resume-BitLocker -MountPoint C:`。Secure Boot を切り替えるときは、**必ず BitLocker を一時停止してから**です。

## アンインストール

この手順で作られるものと、消し方です。

1. **作業フォルダ**：`%USERPROFILE%\snapdragon-npu-work`（`SNPU_WORK` で変えた場合はその場所）を削除します。
2. **Hexagon SDK**：`C:\Qualcomm\Hexagon_SDK` を削除します。`C:\Qualcomm` の中にほかに何もなければ、`C:\Qualcomm` ごと削除してかまいません。
3. **ユーザー環境変数**：Hexagon SDK の導入時に設定されたものを削除します（`OPENCL_SDK_ROOT` は、設定されている場合だけ）。
   ```powershell
   [Environment]::SetEnvironmentVariable('HEXAGON_SDK_ROOT', $null, 'User')
   [Environment]::SetEnvironmentVariable('HEXAGON_TOOLS_ROOT', $null, 'User')
   [Environment]::SetEnvironmentVariable('OPENCL_SDK_ROOT', $null, 'User')
   ```
4. **このリポジトリのフォルダ**と、**モデルファイル**を置いたフォルダを削除します。
5. 手順 0 で入れたツール（LLVM、CMake、Ninja、Git、Python、Node.js、pnpm、Visual Studio）は、ほかで使っていなければ、Windows の「設定」→「アプリ」から削除できます。
6. 付録 A を実行した場合は、[元に戻すとき](#元に戻すとき)の手順も行ってください。

## 背景と謝辞

- 出発点は stable-diffusion.cpp の [PR #1970](https://github.com/leejet/stable-diffusion.cpp/pull/1970)（happyyzy 氏、Local Dream）です。スマートフォン（Snapdragon 8 Elite、HTP v79）で FP8 の DiT を NPU 実行するもので、融合 QKNorm-RoPE と linear2 の分割行列積は、今回ボトルネックとして特定した箇所と一致しました。
- NPU バックエンドは llama.cpp の ggml-hexagon（Qualcomm の開発者を中心に開発）です。
- Microsoft 署名済みの NPU ライブラリと、それに対応する llama.cpp のパッチは、Qualcomm の [GenieX](https://github.com/qualcomm/GenieX) が公開しているものを利用しています。これらのファイルはこのリポジトリには含めず、スクリプトが GenieX の公式リリースから取得します。GenieX のファイルには GenieX のライセンスが適用されます。

## ファイル構成

```
scripts/
  common.ps1          共通設定（モード、固定コミット、GenieX の URL とチェックサム、ツール探索）
  00-check.ps1        環境チェック（変更なし）
  20-get-sources.ps1  ソース取得・パッチ適用・Hexagon SDK 導入・GenieX の署名済みライブラリ取得
  30-build.ps1        ビルド
  50-generate.ps1     生成
  10-make-cert.ps1    （付録 A のみ）署名用証明書の作成と登録
  40-sign-htp.ps1     （付録 A のみ）自作 NPU ライブラリへの署名
patches/
  llama.cpp-ggml-hexagon-inplace-view-src.patch   in-place 演算で落ちる問題の回避
  llama.cpp-ggml-hexagon-geniex-4ff829-workarounds.patch  GenieX 版の NPU カーネルが落ちる形の演算を CPU へ（署名済み構成のみ）
  sdcpp-rope-no-repeat.patch                      RoPE の REPEAT 除去（出力は同一）
```

## ライセンス

MIT License（[LICENSE](LICENSE)）。パッチの対象である llama.cpp と stable-diffusion.cpp も MIT License です。GenieX から取得するファイルには GenieX のライセンスが適用されます。
