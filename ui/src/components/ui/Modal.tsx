"use client";

import { type ReactNode, useEffect, useCallback, useRef } from "react";

interface ModalProps {
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  title?: string;
  /** Optional element to show in the header (e.g. settings gear) */
  headerRight?: ReactNode;
  maxWidth?: string;
}

export function Modal({
  open,
  onClose,
  children,
  title,
  headerRight,
  maxWidth = "max-w-[420px]",
}: ModalProps) {
  const overlayRef = useRef<HTMLDivElement>(null);

  const handleEscape = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    },
    [onClose],
  );

  useEffect(() => {
    if (!open) return;
    document.addEventListener("keydown", handleEscape);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", handleEscape);
      document.body.style.overflow = "";
    };
  }, [open, handleEscape]);

  if (!open) return null;

  return (
    <div
      ref={overlayRef}
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 animate-[fadeIn_0.15s_ease-out]"
      onClick={(e) => {
        if (e.target === overlayRef.current) onClose();
      }}
    >
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" />

      {/* Modal — glass-style, responsive height */}
      <div
        className={`
          relative ${maxWidth} w-full
          max-h-[90vh] sm:max-h-[85vh] flex flex-col
          rounded-t-2xl sm:rounded-2xl
          animate-[slideUp_0.3s_cubic-bezier(0.16,1,0.3,1)]
          overflow-hidden
        `}
        style={{
          boxShadow:
            "0 8px 32px rgba(0,0,0,0.4), 0 0 0 1px rgba(148,163,184,0.06)",
          background:
            "linear-gradient(135deg, rgba(56,189,248,0.08) 0%, rgba(30,41,59,0.35) 50%, rgba(56,189,248,0.04) 100%)",
        }}
      >
        <div className="flex-1 min-h-0 flex flex-col rounded-t-2xl sm:rounded-2xl bg-surface-1/98 backdrop-blur-sm border border-white/[0.06] border-b-0 sm:border-b">
          {/* Header: title and/or close */}
          {(title || true) && (
            <div className="flex items-center justify-between px-4 sm:px-5 py-3 sm:py-4 border-b border-white/[0.06] shrink-0">
              {title ? (
                <h2 className="text-base font-semibold text-text-primary">
                  {title}
                </h2>
              ) : (
                <span />
              )}
              <div className="flex items-center gap-1 ml-auto">
                {headerRight}
                <button
                  type="button"
                  onClick={onClose}
                  className="flex items-center justify-center w-9 h-9 rounded-xl text-text-tertiary hover:text-text-primary hover:bg-surface-3/80 transition-colors cursor-pointer ml-auto"
                  aria-label="Close"
                >
                  <svg
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <line x1="18" y1="6" x2="6" y2="18" />
                    <line x1="6" y1="6" x2="18" y2="18" />
                  </svg>
                </button>
              </div>
            </div>
          )}

          {/* Body — scrollable, responsive padding */}
          <div className="overflow-y-auto flex-1 overscroll-contain px-3 py-4 sm:px-4 sm:py-5 md:px-6 md:py-6">
            {children}
          </div>
        </div>
      </div>
    </div>
  );
}
