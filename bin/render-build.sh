#!/usr/bin/env bash
# Bashシェルを使用することを宣言

set -o errexit
# エラーが発生したらスクリプトを停止

bundle install
# Gemfile に記載された依存関係をインストール

bundle exec rails assets:precompile
# JavaScriptやCSSなどのアセットをプリコンパイル

bundle exec rails assets:clean
# 古いアセットファイルを削除

bundle exec rails db:migrate
# データベースのマイグレーションを実行