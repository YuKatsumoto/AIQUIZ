import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // @ts-expect-error allowedDevOrigins is available at runtime but not yet in this NextConfig type.
  allowedDevOrigins: ['192.168.1.15'],
};

export default nextConfig;
