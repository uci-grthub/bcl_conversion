# Start from a base micromamba image
FROM mambaorg/micromamba:latest

# Set the environment name and copy the environment file
COPY environment.yaml .
ENV ENV_NAME=bcl_convert

# Create the environment and clean up unnecessary files
RUN micromamba create -n $ENV_NAME --file environment.yaml && \
    micromamba clean --all --yes

# Use bash as the default shell and ensure the environment is activated
SHELL ["/bin/bash", "-lc"]

# When the container starts, open an interactive bash shell with the
# conda/micromamba environment activated.
ENTRYPOINT ["bash", "-lc", "micromamba activate $ENV_NAME >/dev/null 2>&1 || source /opt/conda/etc/profile.d/conda.sh && conda activate $ENV_NAME; exec bash"]

# Default to an interactive shell; users can override CMD/ENTRYPOINT to run specific commands.
CMD ["-i"]
