import type { ReactNode, SVGProps } from "react";

type IconProps = SVGProps<SVGSVGElement> & {
  size?: number;
};

type IconBaseProps = IconProps & {
  children: ReactNode;
};

function IconBase({ size = 16, children, ...props }: IconBaseProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...props}
    >
      {children}
    </svg>
  );
}

export function IconSearch(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="11" cy="11" r="7" />
      <line x1="16.65" y1="16.65" x2="21" y2="21" />
    </IconBase>
  );
}

export function IconXCircle(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="12" cy="12" r="9" />
      <line x1="9" y1="9" x2="15" y2="15" />
      <line x1="15" y1="9" x2="9" y2="15" />
    </IconBase>
  );
}

export function IconX(props: IconProps) {
  return (
    <IconBase {...props}>
      <line x1="18" y1="6" x2="6" y2="18" />
      <line x1="6" y1="6" x2="18" y2="18" />
    </IconBase>
  );
}

export function IconMaximize2(props: IconProps) {
  return (
    <IconBase {...props}>
      <polyline points="15 3 21 3 21 9" />
      <polyline points="9 21 3 21 3 15" />
      <line x1="21" y1="3" x2="14" y2="10" />
      <line x1="3" y1="21" x2="10" y2="14" />
    </IconBase>
  );
}

export function IconMinimize2(props: IconProps) {
  return (
    <IconBase {...props}>
      <polyline points="4 14 10 14 10 20" />
      <polyline points="20 10 14 10 14 4" />
      <line x1="14" y1="10" x2="21" y2="3" />
      <line x1="10" y1="14" x2="3" y2="21" />
    </IconBase>
  );
}

export function IconChartLine(props: IconProps) {
  return (
    <IconBase {...props}>
      <polyline points="3 17 9 11 13 15 21 7" />
      <polyline points="21 7 21 13 15 13" />
    </IconBase>
  );
}

export function IconSidebarRight(props: IconProps) {
  return (
    <IconBase {...props}>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <line x1="15" y1="4" x2="15" y2="20" />
    </IconBase>
  );
}

export function IconCalendar(props: IconProps) {
  return (
    <IconBase {...props}>
      <rect x="3" y="4" width="18" height="18" rx="2" />
      <line x1="8" y1="2" x2="8" y2="6" />
      <line x1="16" y1="2" x2="16" y2="6" />
      <line x1="3" y1="10" x2="21" y2="10" />
    </IconBase>
  );
}

export function IconSquares(props: IconProps) {
  return (
    <IconBase {...props}>
      <rect x="4" y="4" width="7" height="7" rx="1" />
      <rect x="13" y="4" width="7" height="7" rx="1" />
      <rect x="4" y="13" width="7" height="7" rx="1" />
      <rect x="13" y="13" width="7" height="7" rx="1" />
    </IconBase>
  );
}

export function IconList(props: IconProps) {
  return (
    <IconBase {...props}>
      <line x1="8" y1="6" x2="21" y2="6" />
      <line x1="8" y1="12" x2="21" y2="12" />
      <line x1="8" y1="18" x2="21" y2="18" />
      <circle cx="4" cy="6" r="1" fill="currentColor" stroke="none" />
      <circle cx="4" cy="12" r="1" fill="currentColor" stroke="none" />
      <circle cx="4" cy="18" r="1" fill="currentColor" stroke="none" />
    </IconBase>
  );
}

export function IconArrowUpCircle(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="12" cy="12" r="9" />
      <polyline points="8 12 12 8 16 12" />
      <line x1="12" y1="16" x2="12" y2="8" />
    </IconBase>
  );
}

export function IconArrowDownCircle(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="12" cy="12" r="9" />
      <polyline points="8 12 12 16 16 12" />
      <line x1="12" y1="8" x2="12" y2="16" />
    </IconBase>
  );
}

export function IconArrowLeft(props: IconProps) {
  return (
    <IconBase {...props}>
      <line x1="19" y1="12" x2="5" y2="12" />
      <polyline points="11 6 5 12 11 18" />
    </IconBase>
  );
}

export function IconHashCircle(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="12" cy="12" r="9" />
      <line x1="9" y1="7" x2="7" y2="17" />
      <line x1="15" y1="7" x2="13" y2="17" />
      <line x1="7" y1="10" x2="17" y2="10" />
      <line x1="6.5" y1="14" x2="16.5" y2="14" />
    </IconBase>
  );
}

export function IconPlusCircle(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="12" cy="12" r="9" />
      <line x1="12" y1="8" x2="12" y2="16" />
      <line x1="8" y1="12" x2="16" y2="12" />
    </IconBase>
  );
}

export function IconStar(props: IconProps) {
  return (
    <IconBase {...props}>
      <polygon points="12 3.8 14.9 9.7 21.3 10.6 16.7 15.1 17.8 21.4 12 18.4 6.2 21.4 7.3 15.1 2.7 10.6 9.1 9.7" />
    </IconBase>
  );
}

export function IconMoreHorizontal(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="6" cy="12" r="1" fill="currentColor" stroke="none" />
      <circle cx="12" cy="12" r="1" fill="currentColor" stroke="none" />
      <circle cx="18" cy="12" r="1" fill="currentColor" stroke="none" />
    </IconBase>
  );
}

export function IconEye(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z" />
      <circle cx="12" cy="12" r="3" />
    </IconBase>
  );
}

export function IconEyeOff(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z" />
      <circle cx="12" cy="12" r="3" />
      <line x1="4" y1="4" x2="20" y2="20" />
    </IconBase>
  );
}

export function IconGitBranch(props: IconProps) {
  return (
    <IconBase {...props}>
      <line x1="6" y1="3" x2="6" y2="15" />
      <circle cx="18" cy="6" r="3" />
      <circle cx="6" cy="18" r="3" />
      <path d="M18 9a9 9 0 0 1-9 9" />
    </IconBase>
  );
}

export function IconFolder(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M3 7v-1a2 2 0 0 1 2-2h5l2 2h9a2 2 0 0 1 2 2v1" />
      <path d="M3 7h18v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
    </IconBase>
  );
}

export function IconCopy(props: IconProps) {
  return (
    <IconBase {...props}>
      <rect x="9" y="9" width="11" height="11" rx="2" />
      <rect x="4" y="4" width="11" height="11" rx="2" />
    </IconBase>
  );
}

export function IconRefresh(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M21 12a9 9 0 1 1-2.64-6.36" />
      <polyline points="21 3 21 9 15 9" />
    </IconBase>
  );
}

export function IconTrash(props: IconProps) {
  return (
    <IconBase {...props}>
      <polyline points="3 6 5 6 21 6" />
      <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
      <path d="M10 11v6" />
      <path d="M14 11v6" />
      <path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" />
    </IconBase>
  );
}

export function IconSettings(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .33 1.87l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06A1.7 1.7 0 0 0 15 19.4a1.7 1.7 0 0 0-1 .62 1.7 1.7 0 0 0-.3 1.52V22a2 2 0 1 1-4 0v-.09a1.7 1.7 0 0 0-.3-1.52 1.7 1.7 0 0 0-1-.62 1.7 1.7 0 0 0-1.87.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-.62-1 1.7 1.7 0 0 0-1.52-.3H2a2 2 0 1 1 0-4h.09a1.7 1.7 0 0 0 1.52-.3 1.7 1.7 0 0 0 .62-1 1.7 1.7 0 0 0-.33-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-.62 1.7 1.7 0 0 0 .3-1.52V2a2 2 0 1 1 4 0v.09a1.7 1.7 0 0 0 .3 1.52 1.7 1.7 0 0 0 1 .62 1.7 1.7 0 0 0 1.87-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.7 1.7 0 0 0 19.4 9c.23.3.52.52.92.62a1.7 1.7 0 0 0 1.52.3H22a2 2 0 1 1 0 4h-.09a1.7 1.7 0 0 0-1.52.3c-.4.1-.7.32-.92.62z" />
    </IconBase>
  );
}

export function IconCode(props: IconProps) {
  return (
    <IconBase {...props}>
      <polyline points="16 18 22 12 16 6" />
      <polyline points="8 6 2 12 8 18" />
    </IconBase>
  );
}

export function IconFile(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <polyline points="14 2 14 8 20 8" />
    </IconBase>
  );
}

export function IconChevronRight(props: IconProps) {
  return (
    <IconBase {...props}>
      <polyline points="9 18 15 12 9 6" />
    </IconBase>
  );
}

export function IconChevronDown(props: IconProps) {
  return (
    <IconBase {...props}>
      <polyline points="6 9 12 15 18 9" />
    </IconBase>
  );
}

export function IconChevronsDownUp(props: IconProps) {
  return (
    <IconBase {...props}>
      <polyline points="7 14 12 9 17 14" />
      <polyline points="7 10 12 15 17 10" />
    </IconBase>
  );
}
