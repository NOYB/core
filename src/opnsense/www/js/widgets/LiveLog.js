/*
 * Copyright (C) 2024 Deciso B.V.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 * OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

export default class LiveLog extends BaseTableWidget {
    constructor(config) {
        super(config);
    }

    getMarkup() {
        let $container = $('<div></div>');
        let $table = this.createTable('live-log-table', {
            headerPosition: 'top',
            rotation: 5,
            headers: [
                this.translations.time,
                this.translations.severity,
                this.translations.process,
                this.translations.message
            ]
        });

        $container.append($table);
        return $container;
    }

    async onMarkupRendered() {
        const params = new URLSearchParams({
            offset: 10,
            searchPhrase: '',
            severity: ''
        }).toString();

        super.openEventSource(`/api/diagnostics/log/core/system/${'live?' + params}`, (event) => {
            if (!event) {
                super.closeEventSource();
            }

            const data = JSON.parse(event.data);

            // Time display format: Use or override log raw time format
            var timefmt = 
                "{{ timefmt }}" == 'Web_GUI_Language' ? "{{ langcode }}"
              : "{{ timefmt }}" == 'Client_Locale' ? 'default'
              : "{{ timefmt }}";

var timefmt = 'default';

            // Implement as Intl.DateTimeFormat object for efficiency (toLocaleString).
            if (timefmt == "{{ langcode }}" || timefmt == 'default') {
                var IDTF_obj = new Intl.DateTimeFormat(timefmt, { month:'short', day:'2-digit', hour:'numeric', hourCycle:'h23', minute: 'numeric', second: 'numeric'});
            }

            switch (timefmt) {
                case 'Log_Raw':
//                    data.timestamp = data.timestamp;
                    break;
                case 'Log_Long':
                    data.timestamp = data.timestamp.substring(0,22).replace('T', ' ');
//                    data.timestamp = data.timestamp.replace(/:[0-9]{2}$/, '').replace('T', ' ');
                    break;
                case 'Log_Long_No_TZ':
                    data.timestamp = data.timestamp.substring(0,19).replace('T', ' ');
//                    data.timestamp = data.timestamp.replace(/(([+-](\d{2}:?\d{2}|\d{1,2}))|Z)$/g, '').replace('T', ' ');
                    break;
                case 'Log_Short':
                    data.timestamp = data.timestamp.substring(5,19).replace('T', ' ');
//                    data.timestamp = data.timestamp.replace(/^\d{4}-|(([+-](\d{2}:?\d{2}|\d{1,2}))|Z)$/g, '').replace('T', ' ');
                    break;
                default:
                    data.timestamp = IDTF_obj.format(new Date(data.timestamp)).replace(/[.,]/g, '');
//                    data.timestamp = new Date(data.timestamp).toLocaleString(timefmt, { month:'short', day:'2-digit', hour:'numeric', hourCycle:'h23', minute: 'numeric', second: 'numeric'}).replace(/[.,]/g, '');
            }

            super.updateTable('live-log-table', [
                [
                    data.timestamp,
                    data.severity,
                    data.process_name,
                    data.line
                ]
            ]);
        });
    }
}
