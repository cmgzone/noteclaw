import Link from "next/link";

const GOOGLE_PLAY_BADGE_URL =
  "https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png";

export function GooglePlayBadge({
  href,
  label = "Get NoteClaw on Google Play",
  className = "",
  external = false,
}: {
  href: string;
  label?: string;
  className?: string;
  external?: boolean;
}) {
  return (
    <Link
      href={href}
      aria-label={label}
      title={label}
      target={external ? "_blank" : undefined}
      rel={external ? "noreferrer" : undefined}
      className={`inline-flex rounded-xl p-2 transition hover:-translate-y-0.5 hover:bg-white/[0.04] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300 ${className}`}
    >
      {/* Google requires the current official badge artwork to remain unmodified. */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={GOOGLE_PLAY_BADGE_URL}
        alt="Get it on Google Play"
        width={646}
        height={250}
        className="h-14 w-auto"
      />
    </Link>
  );
}
