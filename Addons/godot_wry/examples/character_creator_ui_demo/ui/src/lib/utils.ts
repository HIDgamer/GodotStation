import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

export const cn = (...inputs: ClassValue[]) => twMerge(clsx(inputs));

export const postMessage = (type: string, body: object = {}) => {
	// @ts-expect-error: no ipc type
	window.ipc.postMessage(
		JSON.stringify({
			type,
			...body
		})
	);
};
