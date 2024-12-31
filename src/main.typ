#import "@preview/fauxreilly:0.1.1": orly
#import "@preview/codelst:2.0.2": sourcecode

#set page(
  paper: "jis-b5",
)
#set text(
  font: "UDEV Gothic NF",
  size: 10pt,
  lang: "ja",
)
#set document(
  title: "nixpkgs builder-function & Hook book",
  author: "haruki7049",
)
#set heading(
  numbering: "1.1: ",
)
#show raw.where(block: false): box.with(
  fill: luma(240),
  inset: (x: 3pt, y: 0pt),
  outset: (y: 3pt),
  radius: 2pt,
)

// タイトル
#orly(
  font: "Noto Serif JP",
  color: rgb("#85144b"),
  top-text: "Use Nix/NixOS, & Contribute to nixpkgs",
  title: "Function VS Hook in nixpkgs",
  subtitle: "Rust,Zigで比べるNix Derivationの作り方",
)

// 目次
#outline()
#pagebreak()

= 概要

Nixを使用してDerivationを作成するときには、大抵`stdenv.mkDerivation`関数を使用する場合が多いと思う。そうして`stdenv.mkDerivation`関数を使用する時、よく分からないままに、`nativeBuildInputs`アトリビュートに`pkgs.pkg-config`や`pkgs.cmake`などのDerivationを加えた経験がある人もいるのではないだろうか。

簡単に言うと、この`pkgs.cmake`や`pkgs.pkg-config`を`nativeBuildInputs`アトリビュートに加えると、それらは`Hook`として働くようになる。この`Hook`が動作することによって、Nix式の中でCmakeのコマンドライン引数を指定せずとも、デフォルトの設定で良い感じに動かすことができるのだ。

それとは別に、`pkgs.rustPlatform.buildRustPackage`や`pkgs.perlPackages.buildPerlPackage`などの関数でDerivationを作成した経験がある人もいるのではないだろうか。これらは、[Nixpkgs manual stable](https://nixos.org/manual/nixpkgs/stable/)にて、`Language- or framework-specific build helpers`、和訳すると`言語またはフレームワーク固有のビルドヘルパー`という風に、ビルドヘルパーの一種であると書かれている。
今回、この本では`言語またはフレームワーク固有のビルドヘルパー`は簡単のため、`ビルダー関数`と呼ぶ。

この本では、ここまでで話した`Hook`と`ビルダー関数`について深掘りしていく。`Hook`を使用する言語として`Zig言語`、ビルダー関数を使用する言語として`Rust言語`をこの本では使用していく。よくある話として、`Zig言語 vs Rust言語`という話があるが、この本は`Zig言語`と`Rust言語`のどちらが優秀かを議論する本ではなく、単にNixでのDerivationの作り方の違いを挙げる本であることをご留意いただきたい。

それらとは別に、それぞれのチャプターの最後に、簡単な`Hook`や`ビルダー関数`の作り方を書いておくので、参考にしてほしい。

検証環境を以下に書く。この本で参照している`nixpkgs`のコミットハッシュは、`nixpkgs-unstable`ブランチの[8c4dc69](https://github.com/NixOS/nixpkgs/commit/8c4dc69b9732f6bbe826b5fbb32184987520ff26)を使用している。
#sourcecode[
```md
- system: `"aarch64-darwin"`
- host os: `Darwin 24.1.0, macOS 15.1`
- multi-user?: `yes`
- sandbox: `no`
- version: `nix-env (Nix) 2.18.2`
- channels(root): `"nixpkgs"`
- nixpkgs: `/nix/store/63lvc59rjz075kb1f11xww2x2xqpw1pn-source`
```
]

この本の内容で、間違っている点や誤字脱字などがあったら、GitHubにあるリポジトリ、[haruki7049/zenn-articles-repo](https://github.com/haruki7049/zenn-articles-repo)にイシューかプルリクエストを立てていただくか、私のメールアドレスにその旨の電子メールを送ってくれると幸いだ。私のメールアドレスは、[github.com/haruki7049](https://github.com/haruki7049)に載っているので確認いただきたい。

#pagebreak()

== ビルダー関数

`nixpkgs`では、各言語ごとにDerivationを作るための関数が存在する。Dart言語だと`buildDartApplication`、Nim言語だと`buildNimPackage`が挙げられる。これらビルダー関数は、`stdenv.mkDerivation`などの`Derivation`を作成する関数のラッパーとなっていて、プログラミング言語ごとに、Nix式を短く書くために用意されている。

#sourcecode[
```nix
{
  # Import nixpkgs to bind `pkgs` variables
  pkgs = import <nixpkgs> { },
}:

# Call builder function!!
pkgs.rustPlatform.buildRustPackage {
  pname = "test-rust";
  version = "0.1.0";
  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;
}
```
]

#block(
  fill: luma(220),
  inset: (x: 3pt, y: 0pt),
  outset: (y: 3pt),
  radius: 2pt,
  [
    === `<nixpkgs>`はどこに書かれている？

    Nix式を見ていると、稀に以下のように、引数のアトリビュートセット内で値が定義されないまま式が書かれている時があると思う。
    #sourcecode[
```nix
# File name: default.nix
{
  buildDartApplication,
}:

rustPlatform.buildRustPackage {
  pname = "foofoo";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
}
```
    ]
    このように書かれていた場合、`nix-build -E 'with import <nixpkgs> { }; callPackage ./default.nix { }'`というようなコマンドを実行すると良い。
    1. `nix-build -E` -> コマンドライン引数を、Nix式のファイル名のリストとしてではなく、評価されるNix式のリストとして解釈する。
    1. `'with import <nixpkgs> { }; callPackage ./default.nix { }'` -> nixpkgsを`import関数`によって評価して、その中の`callPackage関数`を使用する。`callPackage ./default.nix { }`の第一引数として与えられている`./default.nix`を変更して、評価するNixファイルを変更する。
  ]
)

=== ビルダー関数の実態

ビルダー関数は`stdenv.mkDerivation`等の関数のラッパーだとは話したが、具体的にどのようにそれを実現しているのだろうか。nixpkgs内の[/pkgs/build-support/rust/build-rust-package/default.nix](https://github.com/NixOS/nixpkgs/blob/8c4dc69b9732f6bbe826b5fbb32184987520ff26/pkgs/build-support/rust/build-rust-package/default.nix)に、Rust言語用のビルダー関数、`buildRustPackage`が書かれていたが、私が読んでみたところかなり複雑であった。そこで、私が作った[Janet-lang](https://janet-lang.org)用のビルダー関数、[buildJanetPackage](https://github.com/haruki7049/buildJanetPackage/tree/0.1.0)を見てみよう。

=== buildJanetPackage

[buildJanetPackage](https://github.com/haruki7049/buildJanetPackage/tree/0.1.0)での`buildJanetPackage`関数の実態は、[/lib/buildJanetPackage.nix](https://github.com/haruki7049/buildJanetPackage/blob/0.1.0/lib/buildJanetPackage.nix)に書かれている。以下に記載。

```nix
# /lib/buildJanetPackage.nix

{ pkgs }:

let
  stdenv = pkgs.stdenv;
in
{
  buildJanetPackage =
    { pname
    , version
    , src
    }:
    stdenv.mkDerivation {
      inherit pname version src;

      buildInputs = [
        pkgs.janet
        pkgs.jpm
      ];

      JANET_LIBPATH = "${pkgs.janet}/lib";

      buildPhase = ''
        jpm build
      '';

      installPhase = ''
        mkdir -p $out/bin
        install -m755 build/${pname} $out/bin/${pname}-${version}
      '';
    };
}
```

これを見ていただけるとわかる通り、buildJanetPackage関数は「pnameとversionとsrcを引数に取り`stdenv.mkDerivation`を使用してDerivationを返す関数」である。

> ちなみに、この`/lib/buildJanetPackage.nix`自体は`/default.nix`内の記述、`pkgs.callPackage ./lib/buildJanetPackage.nix { inherit pkgs; }`によって呼び出されている。
>> 今この文章を書いていて思ったことが二点ある。なぜこやつは`pkgs.callPackage`を使用しているのに、引数に`pkgs`を渡しているのかと、それに`pkgs.callPackage`を使用するならば、`/lib/buildJanetPackage.nix`で受け取るものも、`stdenv`を直接受けとれば良いのにということだ。
