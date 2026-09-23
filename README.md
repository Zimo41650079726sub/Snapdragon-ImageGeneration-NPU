# Snapdragon X Elite の NPU で stable-diffusion.cpp を動かす

Windows on Snapdragon（Snapdragon X Elite / Hexagon NPU v73）で、[stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) の拡散モデル本体（DiT）を **NPU（Hexagon HTP）で実行**するための手順とスクリプトです。

- 対象：Windows 11 ARM64 のノートPC（Snapdragon X Elite / X Plus）
- 仕組み：llama.cpp の ggml-hexagon バックエンド（HMX 行列演算ユニットを使う）を stable-diffusion.cpp から使う
- 必要なもの：管理者権限、BIOS 設定の変更（Secure Boot 無効化）、テスト署名モード

> [!WARNING]
> NPU で自作のライブラリを動かすには、Windows を**テスト署名モード**にし、**Secure Boot を無効化**する必要があります。PC のセキュリティが下がります。BitLocker が有効な PC では、手順を誤ると**回復キーの入力を求められ**ます。内容を理解したうえで、自己責任で行ってください。

## 結果

Dell XPS 13 9345（Snapdragon X Elite X1E80100、RAM 64GB）での実測です。512×512、seed 42、同じプロンプトで比較しました。各条件 1 回ずつの計測です。

**FLUX.2 klein 4B（Q4_0）、4 ステップ**

| 実行方法 | TE | DiT（4 ステップ） | VAE | 1 枚の合計 |
|---|---:|---:|---:|---:|
| CPU（WSL2、6 スレッド） | 6.5 秒 | 124.5 秒 | 17.1 秒 | 148.1 秒 |
| CPU（WSL2、12 スレッド） | 3.8 秒 | 90.5 秒 | 23.0 秒 | 117.3 秒 |
| CPU（Windows ネイティブ、12 スレッド） | 4.8 秒 | 112.2 秒 | 15.5 秒 | 132.5 秒 |
| **NPU（この手順）** | 3.9 秒 | **24.5 秒** | 11.2 秒 | **39.6 秒** |

DiT は CPU 最速の条件より **3.7 倍**、1 枚では **3.0 倍**速くなりました。TE（テキストエンコーダ）と VAE は CPU のままです。

**ほかのモデル（NPU、512×512）**

| モデル | ステップ | DiT | 1 枚の合計 | 備考 |
|---|---:|---:|---:|---|
| Z-Image-Turbo（Q4_0） | 8 | 58.4 秒 | 72.3 秒 | 看板の漢字も正しく描けた |
| Krea2-Turbo-HD（Q4_0） | 8 | 91.9 秒 | 109.5 秒 | |
| Qwen-Image-2.1（Q4_0） | 20 | 503.9 秒 | 539.8 秒 | **画像に帯状のノイズが出る（下記「既知の問題」）** |

## 何が効いたか

NPU 上の処理時間を演算ごとに測ると（`GGML_HEXAGON_PROFILE=1`）、行列積は全体の 3% しかなく、最大の行列積で約 10.6 TFLOPS 出ていました。遅さの原因は計算ではなく、データを複製・連結・並べ替える演算でした。

| 対策 | 内容 | 効果（512²、1 ステップの DiT） |
|---|---|---:|
| なし | | 34.7 秒 |
| RoPE の書き換え（`patches/sdcpp-rope-no-repeat.patch`） | 最内次元が 1 のテンソルを複製する REPEAT（NPU 上で 0.1 GB/s、時間の 57%）をなくした。出力はビット単位で同一 | 19.4 秒 |
| CONCAT / CONT を CPU で実行（`GGML_HEXAGON_OPFILTER=CONCAT\|CONT`） | NPU 上のコピー・並べ替えが 0.1〜0.3 GB/s と遅いため | **7.4 秒** |
| （参考）CPU のみ | | 22.2 秒 |

このほか、NPU が落ちる問題を 2 つ回避しています。

- stable-diffusion.cpp 同梱の ggml は Hexagon バックエンドが古く、DSP 側が落ちる（`dspqueue_read failed: 0x72`）→ llama.cpp の ggml を使ってビルドする
- CPU で計算されたテンソルへの in-place 演算が NPU に割り当てられ、ホスト側が落ちる（`0xC0000005`）→ `patches/llama.cpp-ggml-hexagon-inplace-view-src.patch`

## 動作確認環境

| 項目 | バージョン |
|---|---|
| PC | Dell XPS 13 9345（Snapdragon X Elite X1E80100） |
| OS | Windows 11 Home 10.0.26200（ARM64） |
| NPU ドライバ | 30.0.220.3000 |
| Visual Studio | 2026 Community 18.4（MSVC ARM64） |
| LLVM | clang（`winget install LLVM.LLVM`） |
| Hexagon SDK | 6.6.0.0（llama.cpp の `setup-sdk.py` で導入） |
| WDK | 10.0.26100（inf2cat を使用） |
| llama.cpp | `e6ab7c1`（ggml のみ使用） |
| stable-diffusion.cpp | `c92d73c` |

ビルドされる NPU ライブラリは v73 / v75 / v79 / v81 の 4 世代分ですが、**確認したのは v73（X Elite）だけ**です。

## 手順

### 0. 準備：ツールの導入

PowerShell で次を実行します（すでに入っているものは不要です）。

```powershell
winget install LLVM.LLVM
winget install Kitware.CMake
winget install Ninja-build.Ninja
winget install Git.Git
winget install Python.Python.3.12 --architecture arm64
winget install --id Microsoft.WindowsWDK.10.0.26100 -e
```

Visual Studio 2026（Community で可）は Visual Studio Installer から入れ、「C++ によるデスクトップ開発」と **ARM64 用の MSVC ビルドツール**を選びます。

このリポジトリを取得し、スクリプトを実行できるようにします。スクリプトは署名されていないので、**PowerShell を開くたびに**実行ポリシーを一時的に緩めます。

```powershell
git clone https://github.com/Zimo41650079726sub/Snapdragon-ImageGeneration-NPU.git
cd Snapdragon-ImageGeneration-NPU
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\00-check.ps1
```

`00-check.ps1` は現状を表示するだけで、何も変更しません。以降の手順の進み具合もこれで確認できます。

### 1. BitLocker の回復キーを控え、一時停止する（管理者）

BitLocker が有効な PC で Secure Boot を切ると、次の起動で回復キーを求められます。**必ず先に**行ってください。

1. 回復キー（48 桁）を、この PC 以外の場所（スマホの写真、紙など）に控えます。https://account.microsoft.com/devices/recoverykey でも確認できます。管理者の PowerShell で `manage-bde -protectors -get C:` を実行し、表示される ID が控えたキーの ID と一致することを確認します。
2. 管理者の PowerShell で一時停止します。`-RebootCount 0` は「手動で再開するまで停止」という意味です（暗号化は解除されません）。

```powershell
Suspend-BitLocker -MountPoint C: -RebootCount 0
```

### 2. Secure Boot を無効にし、テスト署名を有効にする

1. 再起動して BIOS 設定に入り、**Secure Boot を無効**にします（Dell は起動時に F2。メーカーごとに項目名が違います）。
2. Windows が起動したら、管理者の PowerShell で次を実行し、もう一度再起動します。

```powershell
bcdedit /set testsigning on
```

画面右下に「テスト モード」と表示されれば成功です。Secure Boot が有効なままだと、このコマンドは拒否されます。

### 3. 署名用の証明書を作る（管理者）

管理者の PowerShell で実行します。途中でパスワードの入力画面が 2 回出ます（作成と確認）。最後にもう一度、同じパスワードを入力します。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\10-make-cert.ps1
```

`%USERPROFILE%\Certs\ggml-htp-v1.pfx` ができ、証明書が「信頼されたルート証明機関」と「信頼された発行元」に登録されます。**この pfx を持つ人は、この PC が信頼するコードを作れます。** 大切に保管してください。

### 4. BitLocker を再開する（管理者）

```powershell
Resume-BitLocker -MountPoint C:
```

Secure Boot が無効な状態を正として、保護が再開されます。

### 5. ソースの取得とビルド

ここからは管理者でなくてかまいません。作業フォルダは既定で `%USERPROFILE%\snapdragon-npu-work` です（環境変数 `SNPU_WORK` で変更できます）。

```powershell
.\scripts\20-get-sources.ps1   # llama.cpp と stable-diffusion.cpp を固定コミットで取得し、パッチを適用。Hexagon SDK も導入
.\scripts\30-build.ps1         # 10〜15 分。ログは作業フォルダの build-npu.log
```

### 6. NPU ライブラリへの署名

NPU は署名されていないライブラリを読み込みません。pfx のパスワードを入力します。**ビルドし直したら毎回**実行してください（署名はファイルの中身に対して行われるため）。

```powershell
.\scripts\40-sign-htp.ps1
```

`Successfully verified` と表示されれば完了です。

### 7. 生成

モデルファイルを 1 つのフォルダにまとめて置き、`-ModelDir` で指定します。

```powershell
.\scripts\50-generate.ps1 -Model klein -ModelDir D:\sd-models -Prompt "a lovely cat" -Out cat.png
```

| `-Model` | 拡散モデル | テキストエンコーダ | VAE | 既定ステップ |
|---|---|---|---|---:|
| `klein` | `flux-2-klein-4b-Q4_0.gguf` | `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` | `flux2-vae.safetensors` | 4 |
| `zimage` | `z-image-turbo-Q4_0.gguf` | `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` | `ae.safetensors` | 8 |
| `krea2` | `Krea2-Turbo-HD-V1-Q4_0.gguf` | `Qwen3-VL-4B-Instruct-Uncensored-abliterated.Q4_0.gguf` | `wan_2.1_vae.safetensors` | 8 |
| `qwen21` | `qwen_image_2.1-Q4_0.gguf` | `Qwen3VL-8B-Instruct-Q4_K_M.gguf` | `qwen_image_2.1_vae_bf16.safetensors` | 20 |

ファイル名が違う場合は `-Diffusion` / `-Llm` / `-Vae` で個別に指定できます。`-Cpu` を付けると同じ条件で CPU だけで実行します（比較用）。

**拡散モデルは Q4_0 を使ってください。** NPU の行列演算（HMX）が扱える重みの型は Q4_0 / Q4_1 / Q8_0 / Q4_K / Q6_K / IQ4_NL / MXFP4 / F16 / F32 です（llama.cpp `e6ab7c1` のソースで確認）。Q4_0 で動作と速度を確認しています。

#### sd-cli を直接使う場合

スクリプトがしていることは次の 3 点です。sd-server など、ほかの使い方でも同じ設定が必要です。

```powershell
$env:ADSP_LIBRARY_PATH = "<作業フォルダ>\stable-diffusion.cpp\build-npu\htp"   # 署名済みの NPU ライブラリの場所
$env:GGML_HEXAGON_OPFILTER = "CONCAT|CONT"                                        # 遅い演算を CPU へ
sd-cli.exe ... --backend "diffusion=HTP0,te=cpu,vae=cpu" `
               --params-backend "diffusion=HTP0,te=cpu,vae=cpu" --auto-fit off --diffusion-fa
```

NPU は空きメモリを 0 MiB と報告するため、自動配置（auto-fit）に任せると重みが CPU 側に置かれて動きません。`--params-backend` と `--auto-fit off` で明示してください。flash attention（`--diffusion-fa`）なしでは 3 倍以上遅くなります。

## 既知の問題

- **Qwen-Image-2.1 で画像の横一列に帯状のノイズが出る**：ステップ数（20 / 30）に関係なく、同じ位置に同じ形で出ます。NPU 上の特定の演算で数値が崩れていると見ていますが、原因は未特定です。Qwen-Image-2.1 は当面 `-Cpu` で使ってください。
- **NPU の CONCAT / CONT が遅い**：`GGML_HEXAGON_OPFILTER` で CPU に回して回避しています。NPU 側のカーネルが改善されれば不要になります。
- **VAE と TE は CPU**：1 枚の時間のうち、VAE が約 3 割を占めるようになりました。NPU にも載せられますが、現状は逆効果です（klein、512²）。
  - TE を NPU（`te=HTP0`）：7.1 秒（CPU は約 4 秒）。画像は正常ですが、FP16 計算のため細部が変わります
  - VAE を NPU（`vae=HTP0`）：53.4 秒（CPU は約 10 秒）。さらに縦線状のノイズが出ます

## トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| `bcdedit` が「セキュア ブート ポリシーによって保護されています」 | Secure Boot が有効。手順 2 を参照 |
| 起動時に BitLocker の回復キーを求められた | 手順 1 の一時停止をせずに Secure Boot を変えた。控えた回復キーを入力する |
| PowerShell で `'<' 演算子は将来使用するために予約されています` | 例の `<パスワード>` を記号ごと置き換えていない |
| 長いコマンドを貼り付けると途中で別の行として実行される | 貼り付け時の折り返し。スクリプトを使うか、1 行ずつ貼る |
| ビルドで `UnicodeDecodeError: 'cp932' codec` | 日本語版 Windows の Python の既定文字コード。スクリプトは `PYTHONUTF8=1` を設定済み |
| リンクで `mkvmuxer::...` が未定義 | libwebm。スクリプトは `-DSD_WEBM=OFF` を指定済み |
| `ggml-hex: dspqueue_read failed: 0x00000072` | NPU 側の異常終了。stable-diffusion.cpp 同梱の古い ggml でビルドした場合に発生。llama.cpp の ggml を使う（`30-build.ps1` の設定） |
| アクセス違反 `0xC0000005` で終了 | in-place 演算の問題。`20-get-sources.ps1` がパッチを当てているか確認 |
| NPU を指定したのに速くならない | 署名の不一致、`ADSP_LIBRARY_PATH` の指定漏れ、量子化型が Q4_0 などでない、のいずれか |
| inf2cat が見つからない | WDK が必要。Microsoft のダウンロードページが 404 の場合も winget で入る（手順 0） |

## 元に戻す

1. 管理者の PowerShell で `bcdedit /set testsigning off`
2. `certlm.msc` を開き、「信頼されたルート証明機関」と「信頼された発行元」から `GGML.HTP.v1` を削除
3. `Suspend-BitLocker -MountPoint C: -RebootCount 0`
4. BIOS で Secure Boot を有効に戻す
5. `Resume-BitLocker -MountPoint C:`

Secure Boot を戻すときも、**必ず BitLocker を一時停止してから**です。

## 背景と謝辞

- 出発点は stable-diffusion.cpp の [PR #1970](https://github.com/leejet/stable-diffusion.cpp/pull/1970)（happyyzy 氏、Local Dream）です。スマートフォン（Snapdragon 8 Elite、HTP v79）で FP8 の DiT を NPU 実行するもので、融合 QKNorm-RoPE と linear2 の分割行列積は、今回ボトルネックとして特定した箇所と一致しました。この PR の FP8 経路は v79 以降専用のため、v73 では llama.cpp の HMX（FP16）経路を使っています。
- NPU バックエンドは llama.cpp の ggml-hexagon（Qualcomm の開発者を中心に開発）です。

## ファイル構成

```
scripts/
  common.ps1        共通設定（固定コミット、ツール探索）
  00-check.ps1      環境チェック（変更なし）
  10-make-cert.ps1  署名用証明書の作成と登録（管理者）
  20-get-sources.ps1  ソース取得・パッチ適用・Hexagon SDK 導入
  30-build.ps1      ビルドと NPU ライブラリの配置
  40-sign-htp.ps1   カタログ作成と署名
  50-generate.ps1   生成
patches/
  llama.cpp-ggml-hexagon-inplace-view-src.patch   in-place 演算で落ちる問題の回避
  sdcpp-rope-no-repeat.patch                      RoPE の REPEAT 除去（出力は同一）
```

## ライセンス

MIT License（[LICENSE](LICENSE)）。パッチの対象である llama.cpp と stable-diffusion.cpp も MIT License です。
