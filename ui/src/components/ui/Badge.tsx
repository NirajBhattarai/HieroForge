interface BadgeProps {
  children: React.ReactNode;
  variant?: "default" | "accent" | "success" | "warning";
  className?: string;
}

const variants: Record<string, string> = {
  default: "bg-surface-3 text-text-secondary",
  accent: "bg-accent-muted text-accent",
  success: "bg-success-muted text-success",
  warning: "bg-warning-muted text-warning",
};

export function Badge({
  children,
  variant = "default",
  className = "",
}: BadgeProps) {
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 text-xs font-medium rounded-[--radius-sm] ${variants[variant]} ${className}`}
    >
      {children}
    </span>
  );
}
