ci/
├── build-matrix.yml          # 多芯片构建矩阵定义
├── test-matrix.yml           # 多芯片测试矩阵定义
├── scripts/
│   ├── build-one.sh          # 构建单颗芯片的脚本
│   ├── test-one.sh           # 测试单颗芯片的脚本
│   └── report.sh             # 汇总结果、生成报告
├── boards/
│   ├── rockchip-rk3588.yaml  # 每颗芯片的测试配置
│   ├── nxp-imx8mp.yaml
│   └── ti-am62x.yaml
└── .gitlab-ci.yml            # 或 Jenkinsfile / GitHub Actions