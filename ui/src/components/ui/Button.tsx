"use client";

import { type ButtonHTMLAttributes, forwardRef } from "react";

type Variant = "primary" | "secondary" | "ghost" | "danger";
type Size = "sm" | "md" | "lg";

const variantClasses: Record<Variant, string> = {
  primary:
    "bg-accent text-surface-0 hover:bg-accent-hover active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none shadow-md hover:shadow-lg hover:shadow-accent/20 border border-accent/20",
  secondary:
    "bg-surface-2/80 text-text-primary border border-white/[0.08] hover:border-accent/30 hover:bg-surface-3/80 active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none",
  ghost:
    "bg-transparent text-text-secondary border border-transparent hover:text-text-primary hover:bg-surface-3/80 hover:border-white/[0.06] active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none",
  danger:
    "bg-error-muted text-error border border-error/20 hover:bg-error/20 hover:border-error/30 active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none",
};

const sizeClasses: Record<Size, string> = {
  sm: "px-3.5 py-2 text-sm rounded-xl gap-1.5",
  md: "px-4 py-2.5 text-sm rounded-xl gap-2",
  lg: "px-6 py-3.5 text-base rounded-xl gap-2",
};

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
  loading?: boolean;
  fullWidth?: boolean;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  (
    {
      variant = "primary",
      size = "md",
      loading,
      fullWidth,
      className = "",
      children,
      disabled,
      ...props
    },
    ref,
  ) => {
    return (
      <button
        ref={ref}
        className={`
          inline-flex items-center justify-center font-semibold
          transition-all duration-200 cursor-pointer select-none
          ${variantClasses[variant]}
          ${sizeClasses[size]}
          ${fullWidth ? "w-full" : ""}
          ${loading ? "opacity-70 pointer-events-none" : ""}
          ${className}
        `.trim()}
        disabled={disabled || loading}
        {...props}
      >
        {loading && (
          <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" fill="none">
            <circle
              className="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              strokeWidth="4"
            />
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
            />
          </svg>
        )}
        {children}
      </button>
    );
  },
);
Button.displayName = "Button";
