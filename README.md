# Quarto Docker-Render

This Quarto template uses a project-level pre-render script to render the Quarto notebook inside a docker container to ensure reproducibility.

## How to use it

This template requires a installation of Docker. To test that docker is working, run:
`docker run hello-world:latest`

To use the template, run:
`quarto use template OleBialas/quarto-docker-render`

This will copy the project config file `_quarto.yml` as well as a `scipts/` folder and an `example.qmd` notebook.
If your project already contained a `_quarto.yml` file, you should check it's content to make sure it correctly points to the pre-render script:

```yml
project:
  type: default
  pre-render: ./scripts/docker_prerender.sh
```




## How it works
