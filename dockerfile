# 基础镜像：PyTorch 2.2.2 + CUDA 11.8 + Ubuntu 22.04
FROM pytorch/pytorch:2.2.2-cuda11.8-cudnn8-runtime

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    # 针对V100的优化参数
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    CUDA_ARCH=compute_70 \
    # 内存优化
    PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128 \
    # CUDA兼容设置
    LD_LIBRARY_PATH=/usr/local/cuda/compat:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:$LD_LIBRARY_PATH

# 安装系统依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        wget \
        curl \
        ca-certificates \
        libxml2-dev \
        ninja-build \
        parallel \
        htop \
        ncdu \
        # 添加CUDA 11.8兼容层（解决驱动与CUDA版本不匹配问题）
        cuda-compat-11-8 \
        # 分布式训练依赖
        openssh-client \
        iproute2 \
        net-tools \
        # 性能分析工具
        sysstat \
        linux-tools-generic \
        && \
    # 清理缓存
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# 创建CUDA兼容性链接（解决560驱动与CUDA11.8的兼容问题）
RUN ln -s /usr/local/cuda-11.8 /usr/local/cuda && \
    echo "/usr/local/cuda/compat" >> /etc/ld.so.conf.d/cuda-compat.conf && \
    ldconfig

# 安装flash-attention（V100优化版）
ARG FLASH_ATTN_VERSION=2.5.9
RUN pip install --no-cache-dir flash-attn==${FLASH_ATTN_VERSION} --no-build-isolation

# 复制项目文件（最小化复制以减少构建时间）
COPY pyproject.toml README.md /workspace/
WORKDIR /workspace

# 创建临时olmo目录解决安装依赖问题
RUN mkdir -p olmo && \
    touch olmo/__init__.py && \
    echo 'VERSION = "0.1.0"' > olmo/version.py

# 安装项目依赖
RUN pip install --no-cache-dir .[train] && \
    pip uninstall -y -qq ai2-olmo && \
    # 安装V100特定优化库
    pip install --no-cache-dir nvidia-pyindex && \
    pip install --no-cache-dir nvidia-cuda-runtime-cu11

# 清理和优化
RUN rm -rf olmo/ && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /root/.cache && \
    # 调整共享内存大小限制
    echo "tmpfs /dev/shm tmpfs defaults,size=8g 0 0" >> /etc/fstab

# 设置工作目录和默认命令
WORKDIR /workspace/olmo
CMD ["/bin/bash"]

# 添加健康检查（可选）
# HEALTHCHECK --interval=1m --timeout=10s \
#    CMD nvidia-smi >/dev/null || exit 1