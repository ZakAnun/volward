export type ReleaseBuildOptions = {
  strict?: boolean;
};

export function isStrictReleaseBuild(
  env: Record<string, string | undefined>,
  options: ReleaseBuildOptions = {},
): boolean {
  if (options.strict === true) {
    return true;
  }

  if (options.strict === false) {
    return false;
  }

  const flag = env.WEBSITE_REQUIRE_RELEASE?.trim().toLowerCase();
  return flag === '1' || flag === 'true' || flag === 'yes';
}
