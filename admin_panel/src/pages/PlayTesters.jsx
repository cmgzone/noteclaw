import { createElement, Fragment, useCallback, useEffect, useMemo, useState } from 'react';
import {
    CheckCircle2,
    Clipboard,
    ExternalLink,
    Loader2,
    RefreshCw,
    Save,
    Search,
    Smartphone,
    Users,
} from 'lucide-react';
import api from '../lib/api';

const DEFAULT_OPT_IN_URL = 'https://play.google.com/apps/testing/com.note.claw';
const STATUSES = ['invited', 'authorized', 'active', 'declined'];

function formatDate(value) {
    if (!value) return 'Never';
    return new Date(value).toLocaleString();
}

function formatDay(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return 'Unknown date';
    return date.toLocaleDateString(undefined, {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
    });
}

function formatTime(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return 'Unknown time';
    return date.toLocaleTimeString(undefined, {
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
    });
}

function isHttpsUrl(value) {
    try {
        return new URL(value).protocol === 'https:';
    } catch {
        return false;
    }
}

export default function PlayTesters() {
    const [testers, setTesters] = useState([]);
    const [total, setTotal] = useState(0);
    const [statusCounts, setStatusCounts] = useState({});
    const [copyCounts, setCopyCounts] = useState({ copied: 0, uncopied: 0 });
    const [search, setSearch] = useState('');
    const [status, setStatus] = useState('');
    const [copyFilter, setCopyFilter] = useState('uncopied');
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [busyId, setBusyId] = useState(null);
    const [message, setMessage] = useState('');
    const [error, setError] = useState('');
    const [optInUrl, setOptInUrl] = useState(DEFAULT_OPT_IN_URL);
    const [groupUrl, setGroupUrl] = useState('');
    const [feedbackEmail, setFeedbackEmail] = useState('');

    const loadData = useCallback(async () => {
        setLoading(true);
        setError('');
        try {
            const [testerResponse, settingsResponse] = await Promise.all([
                api.getPlayTesters({
                    search,
                    status,
                    copied: copyFilter === 'copied'
                        ? true
                        : copyFilter === 'uncopied' ? false : '',
                }),
                api.getSettings([
                    'play_test_opt_in_url',
                    'play_test_group_url',
                    'play_test_feedback_email',
                ]),
            ]);
            setTesters(testerResponse.testers || []);
            setTotal(testerResponse.total || 0);
            setStatusCounts(testerResponse.statusCounts || {});
            setCopyCounts(testerResponse.copyCounts || { copied: 0, uncopied: 0 });
            const settings = settingsResponse.settings || {};
            setOptInUrl(settings.play_test_opt_in_url || DEFAULT_OPT_IN_URL);
            setGroupUrl(settings.play_test_group_url || '');
            setFeedbackEmail(settings.play_test_feedback_email || '');
        } catch (loadError) {
            setError(loadError.message || 'Failed to load Play testers');
        } finally {
            setLoading(false);
        }
    }, [copyFilter, search, status]);

    useEffect(() => {
        const timer = setTimeout(loadData, 250);
        return () => clearTimeout(timer);
    }, [loadData]);

    const uncopiedTesters = useMemo(
        () => testers.filter((tester) => !tester.copiedToPlay),
        [testers],
    );

    const groupedTesters = useMemo(() => {
        const groups = [];
        testers.forEach((tester) => {
            const key = new Date(tester.joinedAt).toDateString();
            const currentGroup = groups[groups.length - 1];
            if (!currentGroup || currentGroup.key !== key) {
                groups.push({ key, label: formatDay(tester.joinedAt), testers: [tester] });
            } else {
                currentGroup.testers.push(tester);
            }
        });
        return groups;
    }, [testers]);

    const saveSettings = async (event) => {
        event.preventDefault();
        setError('');
        setMessage('');
        if (!isHttpsUrl(optInUrl)) {
            setError('The Play opt-in URL must be a valid HTTPS URL.');
            return;
        }
        if (groupUrl && !isHttpsUrl(groupUrl)) {
            setError('The Google Group URL must be a valid HTTPS URL.');
            return;
        }

        setSaving(true);
        try {
            await Promise.all([
                api.updateSetting('play_test_opt_in_url', optInUrl.trim()),
                api.updateSetting('play_test_group_url', groupUrl.trim()),
                api.updateSetting('play_test_feedback_email', feedbackEmail.trim()),
            ]);
            setMessage('Play testing settings saved. New invite emails will use these links.');
        } catch (saveError) {
            setError(saveError.message || 'Failed to save testing settings');
        } finally {
            setSaving(false);
        }
    };

    const copyEmails = async () => {
        if (!uncopiedTesters.length) return;
        setBusyId('group-copy');
        setError('');
        setMessage('');
        let copiedToClipboard = false;
        try {
            await navigator.clipboard.writeText(
                uncopiedTesters.map((tester) => tester.email).join('\n'),
            );
            copiedToClipboard = true;
            const response = await api.markPlayTestersCopied(
                uncopiedTesters.map((tester) => tester.id),
                'group',
            );
            setMessage(`Copied and marked ${response.updated} tester email${response.updated === 1 ? '' : 's'} as one Play Console batch.`);
            await loadData();
        } catch (copyError) {
            setError(copiedToClipboard
                ? 'The emails were copied, but they could not be marked as copied. Please try again.'
                : copyError.message || 'Failed to copy tester emails');
        } finally {
            setBusyId(null);
        }
    };

    const copyOneEmail = async (tester) => {
        setBusyId(`copy:${tester.id}`);
        setError('');
        setMessage('');
        let copiedToClipboard = false;
        try {
            await navigator.clipboard.writeText(tester.email);
            copiedToClipboard = true;
            await api.markPlayTestersCopied([tester.id], 'individual');
            setMessage(`Copied ${tester.email} and marked it as individually copied.`);
            await loadData();
        } catch (copyError) {
            setError(copiedToClipboard
                ? 'The email was copied, but it could not be marked as copied. Please try again.'
                : copyError.message || 'Failed to copy tester email');
        } finally {
            setBusyId(null);
        }
    };

    const changeStatus = async (tester, nextStatus) => {
        setBusyId(`status:${tester.id}`);
        setError('');
        try {
            const response = await api.updatePlayTester(tester.id, nextStatus, tester.notes);
            setTesters((current) => current.map((item) => (
                item.id === tester.id ? response.tester : item
            )));
            await loadData();
        } catch (updateError) {
            setError(updateError.message || 'Failed to update tester status');
        } finally {
            setBusyId(null);
        }
    };

    const resendInvite = async (tester) => {
        setBusyId(`resend:${tester.id}`);
        setError('');
        setMessage('');
        try {
            await api.resendPlayTesterInvite(tester.id);
            setMessage(`Invite sent to ${tester.email}.`);
            await loadData();
        } catch (resendError) {
            setError(resendError.message || 'Failed to resend invite');
        } finally {
            setBusyId(null);
        }
    };

    return (
        <div className="space-y-8">
            <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
                <div>
                    <h1 className="flex items-center gap-3 text-2xl font-bold text-gray-900">
                        <Smartphone className="h-7 w-7 text-emerald-600" />
                        Play Testers
                    </h1>
                    <p className="mt-1 text-sm text-gray-500">
                        Manage website signups, Play Console authorization, and testing invitations.
                    </p>
                </div>
                <a
                    href={optInUrl || DEFAULT_OPT_IN_URL}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center justify-center gap-2 rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
                >
                    Open tester opt-in page
                    <ExternalLink className="h-4 w-4" />
                </a>
            </div>

            {(message || error) && (
                <div className={`rounded-lg border p-4 text-sm ${error ? 'border-red-200 bg-red-50 text-red-700' : 'border-emerald-200 bg-emerald-50 text-emerald-700'}`}>
                    {error || message}
                </div>
            )}

            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
                {[
                    ['Total signups', copyCounts.copied + copyCounts.uncopied, Users],
                    ['Not copied', copyCounts.uncopied, Clipboard],
                    ['Copied', copyCounts.copied, CheckCircle2],
                    ['Authorized', statusCounts.authorized || 0, CheckCircle2],
                    ['Active testers', statusCounts.active || 0, Smartphone],
                ].map(([label, value, Icon]) => (
                    <div key={label} className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
                        <div className="flex items-center justify-between">
                            <div>
                                <p className="text-sm text-gray-500">{label}</p>
                                <p className="mt-1 text-2xl font-bold text-gray-900">{value}</p>
                            </div>
                            {createElement(Icon, { className: 'h-6 w-6 text-emerald-600' })}
                        </div>
                    </div>
                ))}
            </div>

            <form onSubmit={saveSettings} className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
                <div className="mb-5">
                    <h2 className="text-lg font-semibold text-gray-900">Invitation settings</h2>
                    <p className="mt-1 text-sm text-gray-500">
                        The opt-in URL is emailed immediately. Add a Google Group URL only when the closed track uses that group.
                    </p>
                </div>
                <div className="grid gap-5 lg:grid-cols-2">
                    <label className="text-sm font-medium text-gray-700">
                        Google Play opt-in URL
                        <input
                            type="url"
                            value={optInUrl}
                            onChange={(event) => setOptInUrl(event.target.value)}
                            required
                            className="mt-2 block w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
                        />
                    </label>
                    <label className="text-sm font-medium text-gray-700">
                        Google Group join URL <span className="font-normal text-gray-400">(optional)</span>
                        <input
                            type="url"
                            value={groupUrl}
                            onChange={(event) => setGroupUrl(event.target.value)}
                            placeholder="https://groups.google.com/g/..."
                            className="mt-2 block w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
                        />
                    </label>
                    <label className="text-sm font-medium text-gray-700 lg:col-span-2">
                        Tester feedback email <span className="font-normal text-gray-400">(optional)</span>
                        <input
                            type="email"
                            value={feedbackEmail}
                            onChange={(event) => setFeedbackEmail(event.target.value)}
                            placeholder="noteclawverify@pikpam.com"
                            className="mt-2 block w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
                        />
                    </label>
                </div>
                <button
                    type="submit"
                    disabled={saving}
                    className="mt-5 inline-flex items-center gap-2 rounded-lg bg-gray-900 px-4 py-2 text-sm font-medium text-white hover:bg-gray-800 disabled:opacity-50"
                >
                    {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                    Save invitation settings
                </button>
            </form>

            <section className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
                <div className="flex flex-col gap-4 border-b border-gray-200 p-5 lg:flex-row lg:items-center lg:justify-between">
                    <div className="flex flex-1 flex-col gap-3 sm:flex-row">
                        <label className="relative flex-1">
                            <Search className="absolute left-3 top-2.5 h-4 w-4 text-gray-400" />
                            <input
                                value={search}
                                onChange={(event) => setSearch(event.target.value)}
                                placeholder="Search testers"
                                className="w-full rounded-lg border border-gray-300 py-2 pl-9 pr-3 text-sm focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
                            />
                        </label>
                        <select
                            value={status}
                            onChange={(event) => setStatus(event.target.value)}
                            className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
                        >
                            <option value="">All statuses</option>
                            {STATUSES.map((value) => <option key={value} value={value}>{value}</option>)}
                        </select>
                        <select
                            value={copyFilter}
                            onChange={(event) => setCopyFilter(event.target.value)}
                            className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
                        >
                            <option value="uncopied">Not copied</option>
                            <option value="copied">Copied</option>
                            <option value="all">All copy states</option>
                        </select>
                    </div>
                    <button
                        type="button"
                        onClick={copyEmails}
                        disabled={!uncopiedTesters.length || busyId === 'group-copy'}
                        className="inline-flex items-center justify-center gap-2 rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50"
                    >
                        {busyId === 'group-copy'
                            ? <Loader2 className="h-4 w-4 animate-spin" />
                            : <Clipboard className="h-4 w-4" />}
                        Copy {uncopiedTesters.length} uncopied email{uncopiedTesters.length === 1 ? '' : 's'}
                    </button>
                </div>

                <div className="border-b border-gray-100 bg-gray-50 px-5 py-3 text-xs text-gray-500">
                    Showing {testers.length} of {total} matching signup{total === 1 ? '' : 's'}. Times use your browser&apos;s local time.
                </div>

                {loading ? (
                    <div className="flex h-48 items-center justify-center text-gray-500">
                        <Loader2 className="mr-2 h-5 w-5 animate-spin" /> Loading testers…
                    </div>
                ) : testers.length === 0 ? (
                    <div className="p-12 text-center text-gray-500">No tester signups yet.</div>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="min-w-full divide-y divide-gray-200">
                            <thead className="bg-gray-50">
                                <tr>
                                    {['Tester', 'Time joined', 'Invite email', 'Copy status', 'Play status', 'Actions'].map((heading) => (
                                        <th key={heading} className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">{heading}</th>
                                    ))}
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100 bg-white">
                                {groupedTesters.map((group) => (
                                    <Fragment key={group.key}>
                                        <tr className="bg-emerald-50/70">
                                            <td colSpan={6} className="px-5 py-3 text-sm font-semibold text-emerald-900">
                                                {group.label}
                                                <span className="ml-2 font-normal text-emerald-700">
                                                    {group.testers.length} signup{group.testers.length === 1 ? '' : 's'}
                                                </span>
                                            </td>
                                        </tr>
                                        {group.testers.map((tester) => (
                                            <tr key={tester.id}>
                                                <td className="px-5 py-4">
                                                    <div className="font-medium text-gray-900">{tester.displayName || 'Unnamed tester'}</div>
                                                    <div className="text-sm text-gray-500">{tester.email}</div>
                                                </td>
                                                <td className="whitespace-nowrap px-5 py-4 text-sm text-gray-600">{formatTime(tester.joinedAt)}</td>
                                                <td className="whitespace-nowrap px-5 py-4 text-sm">
                                                    <span className={tester.inviteEmailSent ? 'text-emerald-700' : 'text-amber-700'}>
                                                        {tester.inviteEmailSent ? `Sent ${formatDate(tester.inviteEmailSentAt)}` : 'Not delivered'}
                                                    </span>
                                                </td>
                                                <td className="whitespace-nowrap px-5 py-4 text-sm">
                                                    {tester.copiedToPlay ? (
                                                        <div>
                                                            <span className="inline-flex rounded-full bg-emerald-100 px-2 py-1 text-xs font-semibold capitalize text-emerald-800">
                                                                Copied {tester.copyMode || ''}
                                                            </span>
                                                            <div className="mt-1 text-xs text-gray-500">{formatDate(tester.copiedAt)}</div>
                                                        </div>
                                                    ) : (
                                                        <span className="inline-flex rounded-full bg-amber-100 px-2 py-1 text-xs font-semibold text-amber-800">
                                                            Not copied
                                                        </span>
                                                    )}
                                                </td>
                                                <td className="px-5 py-4">
                                                    <select
                                                        value={tester.status}
                                                        disabled={busyId?.endsWith(tester.id)}
                                                        onChange={(event) => changeStatus(tester, event.target.value)}
                                                        className="rounded-lg border border-gray-300 px-2 py-1.5 text-sm capitalize focus:border-emerald-500 focus:outline-none"
                                                    >
                                                        {STATUSES.map((value) => <option key={value} value={value}>{value}</option>)}
                                                    </select>
                                                </td>
                                                <td className="px-5 py-4">
                                                    <div className="flex items-center gap-4">
                                                        <button
                                                            type="button"
                                                            onClick={() => copyOneEmail(tester)}
                                                            disabled={busyId?.endsWith(tester.id)}
                                                            className="inline-flex items-center gap-1.5 text-sm font-medium text-gray-700 hover:text-gray-900 disabled:opacity-50"
                                                        >
                                                            {busyId === `copy:${tester.id}`
                                                                ? <Loader2 className="h-4 w-4 animate-spin" />
                                                                : <Clipboard className="h-4 w-4" />}
                                                            {tester.copiedToPlay ? 'Copy again' : 'Copy'}
                                                        </button>
                                                        <button
                                                            type="button"
                                                            onClick={() => resendInvite(tester)}
                                                            disabled={busyId?.endsWith(tester.id)}
                                                            className="inline-flex items-center gap-1.5 text-sm font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50"
                                                        >
                                                            {busyId === `resend:${tester.id}`
                                                                ? <Loader2 className="h-4 w-4 animate-spin" />
                                                                : <RefreshCw className="h-4 w-4" />}
                                                            Resend
                                                        </button>
                                                    </div>
                                                </td>
                                            </tr>
                                        ))}
                                    </Fragment>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </section>
        </div>
    );
}
