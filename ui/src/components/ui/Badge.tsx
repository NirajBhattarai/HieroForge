interface BadgeProps {
  children: React.ReactNode;
  variant?: "default" | "accent" | "success" | "warning";
  className?: string;
}

const variants: Record<string, string> = {
  default: "bg-surface-3/80 text-text-secondary border border-white/[0.06]",
  accent:
    "bg-accent/10 text-accent border border-accent/25 hover:border-accent/40",
  success: "bg-success-muted text-success border border-success/20",
  warning: "bg-warning-muted text-warning border border-warning/20",
};

export function Badge({
  children,
  variant = "default",
  className = "",
}: BadgeProps) {
  return (
    <span
      className={`inline-flex items-center px-2.5 py-1 text-xs font-medium rounded-full transition-colors ${variants[variant]} ${className}`}
    >
      {children}
    </span>
  );
}
