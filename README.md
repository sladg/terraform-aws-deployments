This is a set of terraform modules to simplify deployments.

This is a WIP based on working deployments and limited testing. Use at your own risk.

# Modules

## Next.js standalone

Includes full setup for running Next.js on AWS in Lambdas.
It does setup server function (default), allows for static assets and API routes.
Image optimization is also included.
Requires `output: "standalone"` in `next.config.js`.

## Next.js static

Simple S3 + Cloudfront setup for static Next.js sites.
Requires `output: "export"` in `next.config.js`.
