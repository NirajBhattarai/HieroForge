import type { ReactNode } from 'react'

export type ErrorVariant = 'error' | 'warning'

interface ErrorMessageProps {
  message: string
  id?: string
  variant?: ErrorVariant
  onDismiss?: () => void
  className?: string
  role?: 'alert' | 'status'
  children?: ReactNode
}

const IconError = () => (
  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
    <circle cx="12" cy="12" r="10" />
    <line x1="12" y1="8" x2="12" y2="12" />
    <line x1="12" y1="16" x2="12.01" y2="16" />
  </svg>
)

const IconWarning = () => (
  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
    <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
    <line x1="12" y1="9" x2="12" y2="13" />
    <line x1="12" y1="17" x2="12.01" y2="17" />
  </svg>
)

export function ErrorMessage({
  message,
  id,
  variant = 'error',
  onDismiss,
  className = '',
  role = 'alert',
  children,
}: ErrorMessageProps) {
  const isWarning = variant === 'warning'
  return (
    <div
      id={id}
      className={`error-message error-message--${variant} ${className}`.trim()}
      role={role}
    >
      <span className="error-message-icon" aria-hidden>
        {isWarning ? <IconWarning /> : <IconError />}
      </span>
      <span className="error-message-text">{message}</span>
      {children}
      {onDismiss && (
        <button
          type="button"
          className="error-message-dismiss"
          onClick={onDismiss}
          aria-label="Dismiss"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>
      )}
    </div>
  )
}
