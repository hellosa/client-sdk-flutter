#!/bin/bash

# 🚀 LiveKit Flutter Web 手动部署脚本

echo "🔧 构建 Web 应用..."
cd example
flutter build web --base-href /client-sdk-flutter/
cd ..

echo "📦 准备 gh-pages 分支..."
# 保存当前分支
current_branch=$(git branch --show-current)

# 切换到 gh-pages 分支（如果不存在则创建）
if git show-ref --verify --quiet refs/heads/gh-pages; then
    git checkout gh-pages
else
    git checkout --orphan gh-pages
    git rm -rf --cached .
    rm -rf * .github .gitignore
fi

# 复制构建文件
echo "📁 复制构建文件..."
cp -r example/build/web/* .

# 提交并推送
echo "📤 提交并推送到 GitHub..."
git add .
git commit -m "🚀 Deploy LiveKit Flutter Web App - $(date)"
git push origin gh-pages

# 回到原分支
git checkout $current_branch

echo "✅ 部署完成！"
echo "🌐 访问地址：https://hellosa.github.io/client-sdk-flutter/"