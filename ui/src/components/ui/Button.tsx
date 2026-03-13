"use client";

import { type ButtonHTMLAttributes, forwardRef } from "react";

type Variant = "primary" | "secondary" | "ghost" | "danger";
type Size = "sm" | "md" | "lg";

const variantClasses: Record<Variant, string> = {
  primary:
    "bg-accent text-surface-0 hover:bg-accent-hover active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none shadow-sm",
  secondary:
    "bg-accent-muted text-accent hover:bg-accent-soft active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none",
  ghost:
    "bg-transparent text-text-secondary hover:text-text-primary hover:bg-surface-3 active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none",
  danger:
    "bg-error-muted text-error hover:bg-error/20 active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none",
};

const sizeClasses: Record<Size, string> = {
  sm: "px-3 py-1.5 text-sm rounded-[--radius-sm] gap-1.5",
  md: "px-4 py-2.5 text-sm rounded-[--radius-md] gap-2",
  lg: "px-6 py-3.5 text-base rounded-[--radius-lg] gap-2",
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
